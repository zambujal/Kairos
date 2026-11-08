// tb_kairos.cpp: o banco de ensaio do core do Kairos (Verilator). Faz de placa a' volta do core_kairos:
//   - os relogios (54 MHz; 27 MHz para a DivTIESUS) e os ce do Z80 / do quadro como o top.vhd (3,5 MHz);
//   - a SDRAM (64 Mbit, 32 bits, CL 2), com os bytes num vector (sdm);
//   - o cartao SD (SDHC em SPI) sobre uma imagem (SDIMG); as escritas (CMD24/25) vao para a imagem;
//   - o teclado (a matriz de 40 teclas), o botao do NMI e o reset;
//   - a FDD3000: a memoria da FDD (2 MB, feita pelo dsk_fdd.py), a ROM do TI e o arranque, como o plugin DSK.
// As ROMs do Timex e do esxDOS estao nas memorias desde o inicio (home.hex, esx.hex: ver o mem_sim.v).
//
// Uso:  SDIMG=cartao.img [EVENTOS=ev.txt] [LOAD=estado.st] sim_kairos T_FIM_ms
// Eventos (um por linha, "ms COMANDO argumento"; # = comentario):
//   KEYS texto     carrega nas teclas, uma de cada vez (KHOLD / KGAP ms, 80 por omissao). Letras e algarismos sao
//                  as teclas; ~ ENTER, _ ESPACO, # CAPS SHIFT, $ SYMBOL SHIFT, ! BREAK (CAPS+ESPACO), . (SYM+M),
//                  ^x = CAPS SHIFT + x, %x = SYMBOL SHIFT + x
//   NMI [ms]       o botao do NMI (0,1 ms por omissao)
//   RST [ms]       reset do Timex (1,2 ms por omissao, como o A7h bit 2 do core)
//   SCR nome       o ecra para nome.v16 (os 32K da RAM de video, a porta FF, a cor do hi-res, o border e o banco)
//   SCRS ms        um ecra a cada ms (ecra_tNNNNN.v16); SCRS 0 para
//   MEM nome       a RAM do Timex (4000-FFFF, 48K) para nome.ram e a da FDD (64K) para nome.fdd
//   SAVE fich      guarda o estado (continua-se com LOAD=fich)
//   FIM            acaba
//   TIROM fich     a ROM do Timex Interface (4K) para a memoria do TI
//   FDDP fich      (2026-11-08) o mesmo sem o reset do Timex: como o plugin, que espera pelo TOS e so' depois o faz (RST)
//   FDD fich       a memoria da FDD (2 MB do dsk_fdd.py), a FDD ligada com disco, o Z80 dela do inicio e o reset do
//                  Timex: como o plugin DSK (A0h = 1, A1h, A7h = 1, A0h = 0, A7h = 5)
//   DISCO fich     so' o disco (a parte de 100000h de um fdd.bin), sem reset: a troca de disco
//   FDDRESET [ms]  o botao de reset do controlador (so' o Z80 da FDD)
//   SEMDISCO       a drive fica sem disco
// Ambiente: TRACO=ini,fim (ms): os saltos do Z80 do Timex em traco.txt; TRACOFDD=ini,fim: os do Z80 da FDD em
//   traco_fdd.txt. NMIMS: o NMI em ms. ESTADO=ms: a linha de estado a cada ms (250 por omissao).
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include "Vcore_kairos.h"
#include "Vcore_kairos___024root.h"
#include "Vcore_kairos_core_kairos.h"
#include "Vcore_kairos_ram_dp__Af.h"
#include "verilated.h"
#include "verilated_save.h"
#include "nomes.h"

static const long long CICLOS_MS = 54000;           // 54 MHz
static uint32_t sdm[1 << 21];                       // a SDRAM: 2M palavras de 32 bits (8 MB)
static FILE* sdf;                                   // a imagem do cartao
static Vcore_kairos* G;

// ---------------------------------------------------------------- o estado do banco (guardado com o SAVE)
struct SD {
  uint8_t cs_ant, sclk_ant, miso, rx, out_cur;
  int nb, ncmd, estado, wn, multi_w, lendo, app, idle, n41;
  uint8_t cmd[6], wbuf[516];
  uint32_t wbloco, rbloco;
  uint8_t q[4096]; int qh, qn;                      // fila de saida (anel)
  long ncmds, n17, n18, n24;
};
struct E {
  long long cyc;
  int ev_idx;
  // ce / ce35 como o top.vhd (3,5 MHz certos com denominador 54000)
  int acc35; uint8_t ce_r, ce35_r;
  // SDRAM: linha aberta de cada banco e a palavra que sai no barramento no flanco seguinte
  uint16_t linha[4]; uint8_t lido_v; uint32_t lido;
  SD sd;
  // teclas
  char keys[256]; int k_idx; long long k_prox; bool k_baixo;
  // NMI e reset
  long long t_nmi_fim, t_rst_fim, t_fddrst_fim, t_gsrst_fim;
  // ecras periodicos
  long long scr_per, scr_prox;
  // para a linha de estado
  uint8_t f2t_ant, t2f_ant, pag_ant, nmi_ant, est_ant; int n_lig;
};
static E e;
static SD& s = e.sd;

struct Ev { double ms; std::string cmd, arg; };

// mudar um registo do core: escreve-se o registo (R_x) e a entrada D dele (DR_x) durante 4 flancos. So' o R_x nao
// chega quando o D e' um fio guardado pelo Verilator (no flanco seguinte o registo volta ao valor antigo); so' o D
// nao chega quando o Verilator o recalcula antes do flanco.
struct Poe { CData* r; CData* d; uint8_t v; int n; };
static std::vector<Poe> poes;
#define POE(sinal, valor) poes.push_back({&c->R_##sinal, &c->DR_##sinal, (uint8_t)(valor), 4})
static std::vector<Ev> evs;
static bool fdd_sem_rst = false;                    // (2026-11-08) FDDP: a FDD arranca sem o reset do Timex (o RST depois)

// ---------------------------------------------------------------- SDRAM
static void sdram_byte(uint32_t a, uint8_t v) {
  uint32_t w = (a >> 2) & ((1 << 21) - 1); int b = (a & 3) * 8;
  sdm[w] = (sdm[w] & ~(0xFFu << b)) | ((uint32_t)v << b);
}
static uint8_t sdram_le(uint32_t a) { return (sdm[(a >> 2) & ((1 << 21) - 1)] >> ((a & 3) * 8)) & 0xFF; }
static size_t carrega(const char* fn, uint32_t base, size_t n_max, size_t desde = 0) {
  FILE* f = fopen(fn, "rb");
  if (!f) { fprintf(stderr, "nao abro %s\n", fn); exit(1); }
  std::vector<uint8_t> b(n_max);
  fseek(f, (long)desde, SEEK_SET);
  size_t n = fread(b.data(), 1, n_max, f);
  fclose(f);
  for (size_t i = 0; i < n; i++) sdram_byte(base + (uint32_t)i, b[i]);
  return n;
}
// no flanco descendente do clk (o flanco de subida da SDRAM, que recebe o relogio invertido)
static void sdram_flanco(Vcore_kairos* t) {
  // a palavra de um READ do flanco anterior vai para o barramento (o core apanha-a no flanco descendente seguinte;
  // numa leitura simples so' a usa um flanco depois, e o barramento mantem-na)
  if (e.lido_v) { t->sd_dq_i = e.lido; e.lido_v = 0; }
  int cmd = (t->sd_cs_n << 3) | (t->sd_ras_n << 2) | (t->sd_cas_n << 1) | t->sd_we_n;
  int ba = t->sd_ba & 3;
  uint32_t ad = t->sd_addr;
  if (cmd == 0x3) e.linha[ba] = ad & 0x7FF;                                    // ACT
  else if (cmd == 0x5 || cmd == 0x4) {                                         // READ / WRITE
    uint32_t w = ((uint32_t)ba << 19) | ((uint32_t)e.linha[ba] << 8) | (ad & 0xFF);
    if (cmd == 0x5) { e.lido = sdm[w]; e.lido_v = 1; }
    else {
      uint32_t d = t->sd_dq_o, m = 0;
      for (int i = 0; i < 4; i++) if (!((t->sd_dqm >> i) & 1)) m |= 0xFFu << (i * 8);
      sdm[w] = (sdm[w] & ~m) | (d & m);
    }
  }
}

// ---------------------------------------------------------------- cartao SD (SDHC, SPI modo 0)
static void sd_poe(uint8_t b) { if (s.qn < (int)sizeof s.q) { s.q[(s.qh + s.qn) % sizeof s.q] = b; s.qn++; } }
static void sd_bloco(uint32_t bloco) {
  uint8_t b[512];
  memset(b, 0, sizeof b);
  if (fseek(sdf, (long)bloco * 512, SEEK_SET) == 0) { size_t n = fread(b, 1, 512, sdf); (void)n; }
  sd_poe(0xFF); sd_poe(0xFE);
  for (int i = 0; i < 512; i++) sd_poe(b[i]);
  sd_poe(0xFF); sd_poe(0xFF);
}
static uint8_t sd_tira() {
  if (s.qn == 0 && s.lendo) { sd_bloco(s.rbloco++); s.n18++; }
  if (s.qn == 0) return 0xFF;
  uint8_t b = s.q[s.qh]; s.qh = (s.qh + 1) % sizeof s.q; s.qn--;
  return b;
}
static void sd_r1(uint8_t r) { sd_poe(0xFF); sd_poe(r); }
static void sd_comando() {
  int idx = s.cmd[0] & 0x3F;
  uint32_t arg = ((uint32_t)s.cmd[1] << 24) | (s.cmd[2] << 16) | (s.cmd[3] << 8) | s.cmd[4];
  bool app = s.app; s.app = 0;
  s.ncmds++;
  if (idx == 12) { s.lendo = 0; s.qn = 0; sd_poe(0xFF); sd_poe(0x00); sd_poe(0xFF); return; }
  s.qn = 0;
  switch (idx) {
    case 0: s.idle = 1; s.n41 = 0; sd_r1(0x01); break;
    case 8: sd_r1(0x01); sd_poe(0x00); sd_poe(0x00); sd_poe(0x01); sd_poe(arg & 0xFF); break;
    case 55: s.app = 1; sd_r1(s.idle); break;
    case 41: if (app && ++s.n41 >= 2) s.idle = 0; sd_r1(s.idle); break;
    case 1: s.idle = 0; sd_r1(0); break;
    case 58: sd_r1(s.idle); sd_poe(0xC0); sd_poe(0xFF); sd_poe(0x80); sd_poe(0x00); break;   // SDHC (CCS = 1)
    case 9: case 10: {                                                                         // CSD / CID
      long tam = 0; if (fseek(sdf, 0, SEEK_END) == 0) tam = ftell(sdf);
      uint32_t c = (uint32_t)(tam / (512 * 1024)); if (c) c--;
      uint8_t csd[16] = {0x40, 0x0E, 0x00, 0x32, 0x5B, 0x59, 0x00, (uint8_t)((c >> 16) & 0x3F), (uint8_t)(c >> 8), (uint8_t)c,
                         0x7F, 0x80, 0x0A, 0x40, 0x00, 0x01};
      uint8_t cid[16] = {0x03, 'K', 'R', 'K', 'A', 'I', 'R', 'O', 0x10, 0, 0, 0, 1, 0x01, 0x6A, 0x01};
      sd_r1(0); sd_poe(0xFF); sd_poe(0xFE);
      for (int i = 0; i < 16; i++) sd_poe(idx == 9 ? csd[i] : cid[i]);
      sd_poe(0xFF); sd_poe(0xFF);
      break; }
    case 17: s.n17++; sd_r1(0); sd_bloco(arg); break;
    case 18: sd_r1(0); s.lendo = 1; s.rbloco = arg; break;
    case 24: s.n24++; sd_r1(0); s.estado = 1; s.wbloco = arg; s.multi_w = 0; break;
    case 25: sd_r1(0); s.estado = 1; s.wbloco = arg; s.multi_w = 1; break;
    case 13: sd_r1(0); sd_poe(0); break;
    default: sd_r1(app || idx == 16 || idx == 59 || idx == 23 ? 0x00 : 0x04); break;
  }
}
static void sd_recebe(uint8_t b) {
  if (s.estado == 1) {                              // a espera do token do bloco a escrever
    if (b == 0xFE || b == 0xFC) { s.estado = 2; s.wn = 0; }
    else if (b == 0xFD) { s.estado = 0; sd_poe(0xFF); sd_poe(0x00); sd_poe(0xFF); }   // fim do CMD25
    return;
  }
  if (s.estado == 2) {                              // 512 bytes e o CRC
    s.wbuf[s.wn++] = b;
    if (s.wn == 514) {
      if (fseek(sdf, (long)s.wbloco * 512, SEEK_SET) == 0) { fwrite(s.wbuf, 1, 512, sdf); fflush(sdf); }
      sd_poe(0x05); sd_poe(0x00); sd_poe(0x00); sd_poe(0xFF);
      if (s.multi_w) { s.wbloco++; s.estado = 1; } else s.estado = 0;
    }
    return;
  }
  if (s.ncmd == 0 && (b & 0xC0) != 0x40) return;
  s.cmd[s.ncmd++] = b;
  if (s.ncmd == 6) { s.ncmd = 0; sd_comando(); }
}
static void sd_spi(Vcore_kairos* t) {
  uint8_t cs = t->mmc_cs_n, sclk = t->mmc_sclk;
  if (cs && !s.cs_ant) { s.nb = 0; s.ncmd = 0; }
  if (!cs && s.cs_ant) { s.nb = 0; s.out_cur = sd_tira(); s.miso = s.out_cur >> 7; }
  if (!cs) {
    if (sclk && !s.sclk_ant) {                      // subida: o cartao le' o MOSI
      s.rx = (uint8_t)((s.rx << 1) | (t->mmc_mosi & 1));
      if (++s.nb == 8) { s.nb = 0; sd_recebe(s.rx); s.out_cur = sd_tira(); }
    } else if (!sclk && s.sclk_ant) {               // descida: o bit seguinte no MISO
      s.miso = (s.out_cur >> (7 - s.nb)) & 1;
    }
  }
  t->mmc_miso = cs ? 1 : s.miso;
  s.cs_ant = cs; s.sclk_ant = sclk;
}

// ---------------------------------------------------------------- teclas, ecras, memoria
static int bit_tecla(char c) {
  static const char* filas[8] = {"#ZXCV", "ASDFG", "QWERT", "12345", "09876", "POIUY", "~LKJH", "_$MNB"};
  if (c >= 'a' && c <= 'z') c -= 32;
  for (int f = 0; f < 8; f++) for (int k = 0; k < 5; k++) if (filas[f][k] == c) return f * 5 + k;
  return -1;
}
static uint64_t mat_tecla(const char* k, int* usados) {
  *usados = 1;
  if (k[0] == '!') return (1ULL << 0) | (1ULL << 35);                 // BREAK
  if (k[0] == '.') return (1ULL << 36) | (1ULL << 37);                // SYM + M
  if ((k[0] == '^' || k[0] == '%') && k[1]) {
    *usados = 2; int b = bit_tecla(k[1]);
    return (k[0] == '^' ? 1ULL << 0 : 1ULL << 36) | (b >= 0 ? 1ULL << b : 0);
  }
  int b = bit_tecla(k[0]);
  return b >= 0 ? 1ULL << b : 0;
}
static void ecra(const char* nome) {
  char fn[300]; snprintf(fn, sizeof fn, "%s.v16", nome);
  FILE* o = fopen(fn, "wb");
  auto* c = G->rootp->core_kairos;
  for (int i = 0; i < 32768; i++) fputc(c->scr->m[i], o);
  fputc(c->R_regff, o); fputc(G->hcor, o); fputc(G->border, o); fputc(G->ecra7, o);   // a porta FF (o modo do Timex)
  fclose(o);
}
static void memoria(const char* nome) {
  char fn[300]; snprintf(fn, sizeof fn, "%s.ram", nome);
  FILE* o = fopen(fn, "wb");
  auto* c = G->rootp->core_kairos;
  for (int i = 0; i < 16384; i++) fputc(c->scr->m[i], o);                 // 4000-7FFF (o banco 5)
  for (int i = 0; i < 32768; i++) fputc(sdram_le(i), o);                  // 8000-FFFF (a RAM interna)
  fclose(o);
  snprintf(fn, sizeof fn, "%s.fdd", nome);
  o = fopen(fn, "wb");
  for (int i = 0; i < 65536; i++) fputc(sdram_le(0x410000 + i), o);      // a RAM do Z80 da FDD
  fclose(o);
}

// ---------------------------------------------------------------- o banco
int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  double T_FIM = argc > 1 ? atof(argv[1]) : 5000;
  const char* img = getenv("SDIMG");
  if (!img) { fprintf(stderr, "falta SDIMG (a imagem do cartao)\n"); return 1; }
  sdf = fopen(img, "r+b");
  if (!sdf) { perror(img); return 1; }
  if (getenv("EVENTOS")) {
    FILE* f = fopen(getenv("EVENTOS"), "r"); char l[512];
    while (f && fgets(l, sizeof l, f)) {
      double ms; char c[32] = "", a[400] = "";
      if (l[0] == '#' || sscanf(l, "%lf %31s %399[^\n]", &ms, c, a) < 2) continue;
      evs.push_back({ms, c, a});
    }
    if (f) fclose(f);
    std::stable_sort(evs.begin(), evs.end(), [](const Ev& x, const Ev& y) { return x.ms < y.ms; });
  }
  const long long KHOLD = (getenv("KHOLD") ? atoi(getenv("KHOLD")) : 80) * CICLOS_MS;
  const long long KGAP = (getenv("KGAP") ? atoi(getenv("KGAP")) : 80) * CICLOS_MS;
  const long long NMI_C = getenv("NMIMS") ? (long long)(atof(getenv("NMIMS")) * CICLOS_MS) : 5400;
  const long long EST_C = (getenv("ESTADO") ? atoi(getenv("ESTADO")) : 250) * CICLOS_MS;
  double tr_i = -1, tr_f = -1, trf_i = -1, trf_f = -1;
  if (getenv("TRACO")) sscanf(getenv("TRACO"), "%lf,%lf", &tr_i, &tr_f);
  if (getenv("TRACOFDD")) sscanf(getenv("TRACOFDD"), "%lf,%lf", &trf_i, &trf_f);
  FILE* tr = tr_i >= 0 ? fopen("traco.txt", "w") : nullptr;
  FILE* trf = trf_i >= 0 ? fopen("traco_fdd.txt", "w") : nullptr;
  // (2026-11-08) FDCLOG=ini,fim (ms): cada comando do WD1770 da FDD3000 em fdc.txt (inicio e fim do busy)
  double fc_i = -1, fc_f = -1;
  if (getenv("FDCLOG")) sscanf(getenv("FDCLOG"), "%lf,%lf", &fc_i, &fc_f);
  FILE* fcl = fc_i >= 0 ? fopen("fdc.txt", "w") : nullptr;
  int busy_ant = 0, face_ant = -1, drv_ant = -1;

  auto* t = new Vcore_kairos; G = t;
  auto* c = t->rootp->core_kairos;
  memset(&e, 0, sizeof e);
  e.k_idx = -1; s.cs_ant = 1; s.miso = 1; s.out_cur = 0xFF; s.idle = 1;
  t->reset_n = 0; t->nmi_n = 1; t->mat = 0; t->turbo = 0; t->mmc_miso = 1;
  bool retomado = false;
  if (getenv("LOAD")) {
    VerilatedRestore is; is.open(getenv("LOAD"));
    is >> *t; is.read(&e, sizeof e); is.read(sdm, sizeof sdm); is.close();
    retomado = true;
    e.ev_idx = 0;                                                  // os eventos sao os deste ficheiro: salta os que ja' passaram
    while (e.ev_idx < (int)evs.size() && evs[e.ev_idx].ms * CICLOS_MS < e.cyc) e.ev_idx++;
    printf("%10.3f ms estado retomado de %s\n", e.cyc / (double)CICLOS_MS, getenv("LOAD"));
  }
  const long long N = (long long)(T_FIM * CICLOS_MS);
  bool sdram_pronta = retomado;
  long long prox_est = (e.cyc / EST_C + 1) * EST_C;
  uint16_t pc_ant = 0, pcf_ant = 0, pc_m1 = 0, pcf_m1 = 0; uint8_t m1_ant = 1, m1f_ant = 1;
  int mo_ant = -1, hc_ant = -1, ff7_ant = -1, hsr_ant = -1, pag_tr = -1;
  uint16_t salto_de = 0, salto_para = 0; long repete = 0;
  uint16_t saltof_de = 0, saltof_para = 0; long repetef = 0;
  uint16_t fe_a = 0; bool fe_rd = false; long n_fe = 0, n_fant = 0;   // (2026-11-06) as leituras do teclado
  bool luz_ant = false; long n_luz = 0; double luz_ms = 0;              // (89) a luz da drive (o WD1770 ocupado)

  for (long long& cyc = e.cyc; cyc < N; ) {
    const double ms = cyc / (double)CICLOS_MS;
    // ---- flanco de subida
    for (size_t i = 0; i < poes.size();) {
      if (poes[i].n-- <= 0) poes.erase(poes.begin() + i);
      else { *poes[i].r = poes[i].v; *poes[i].d = poes[i].v; i++; }
    }
    t->ce = e.ce_r; t->ce35 = e.ce35_r;
    t->clk = 1; t->vclk = 1; t->clk_div = (cyc & 1) ? 0 : 1;
    t->eval();
    sd_spi(t);
    {   // o ce do Z80 e o ce35 para o ciclo seguinte (top.vhd, velocidade 1 x)
      int ms_ = t->maq_st;
      int n1 = ((ms_ >> 8) & 1) && ((ms_ >> 7) & 1) ? 3584 : ((ms_ >> 8) & 1) && ((ms_ >> 2) & 1) ? 3545 : 3500;
      int a35 = e.acc35 + n1;
      bool c1 = e.acc35 < 27000 && a35 >= 27000;
      bool c4 = (e.acc35 < 6750 && a35 >= 6750) || (e.acc35 < 20250 && a35 >= 20250) ||
                (e.acc35 < 33750 && a35 >= 33750) || (e.acc35 < 47250 && a35 >= 47250);
      e.ce_r = t->dv_lento ? c1 : t->arr_rapido ? c4 : c1;
      if (a35 >= 54000) { e.acc35 = a35 - 54000; e.ce35_r = 1; } else { e.acc35 = a35; e.ce35_r = 0; }
    }
    // ---- flanco de descida
    t->clk = 0; t->vclk = 0;
    t->eval();
    sdram_flanco(t);
    cyc++;

    // ---- a placa: reset, NMI, teclas, carregamentos
    if (!retomado && cyc == CICLOS_MS) t->reset_n = 1;                    // 1 ms de reset ao ligar
    if (e.t_rst_fim && cyc == e.t_rst_fim) { t->reset_n = 1; e.t_rst_fim = 0; printf("%10.3f ms o Timex arranca\n", ms); }
    if (e.t_nmi_fim && cyc == e.t_nmi_fim) { t->nmi_n = 1; e.t_nmi_fim = 0; }
    if (e.t_gsrst_fim && cyc == e.t_gsrst_fim) {                           // fim do carregamento da FDD (A0h = 0, A7h = 5)
      POE(gs_rst, 0); e.t_gsrst_fim = 0;
      if (fdd_sem_rst) { fdd_sem_rst = false; printf("%10.3f ms a FDD arranca (o Timex sem reset: FDDP)\n", ms); }
      else { t->reset_n = 0; e.t_rst_fim = cyc + 65536; }
      printf("%10.3f ms o Z80 da FDD arranca; reset do Timex\n", ms);
    }
    if (e.t_fddrst_fim && cyc == e.t_fddrst_fim) { POE(gs_rst, 0); e.t_fddrst_fim = 0; printf("%10.3f ms a FDD arranca outra vez\n", ms); }
    if (!sdram_pronta && t->pronta) { sdram_pronta = true; printf("%10.3f ms SDRAM pronta (teste %d %d)\n", ms, t->sd_teste, t->sd_teste2); }
    if (e.k_idx >= 0 && cyc >= e.k_prox) {
      if (!e.k_baixo) {
        if (e.keys[e.k_idx] == 0) { e.k_idx = -1; printf("%10.3f ms teclas acabadas\n", ms); }
        else { int u; t->mat = mat_tecla(&e.keys[e.k_idx], &u); e.k_idx += u - 1; e.k_baixo = true; e.k_prox = cyc + KHOLD; }
      } else { t->mat = 0; e.k_baixo = false; e.k_idx++; e.k_prox = cyc + KGAP; }
    }
    if (e.scr_per > 0 && cyc >= e.scr_prox) {
      char fn[64]; snprintf(fn, sizeof fn, "ecra_t%05d", (int)ms); ecra(fn); e.scr_prox = cyc + e.scr_per;
    }

    // ---- eventos
    while (sdram_pronta && e.ev_idx < (int)evs.size() && cyc >= (long long)(evs[e.ev_idx].ms * CICLOS_MS)) {
      Ev& v = evs[e.ev_idx++]; e.n_lig = 0;
      const char* a = v.arg.c_str();
      printf("%10.3f ms evento %s %s\n", ms, v.cmd.c_str(), a); fflush(stdout);
      if (v.cmd == "NMI") { t->nmi_n = 0; e.t_nmi_fim = cyc + (*a ? (long long)(atof(a) * CICLOS_MS) : NMI_C); }
      else if (v.cmd == "RST") { t->reset_n = 0; e.t_rst_fim = cyc + (*a ? (long long)(atof(a) * CICLOS_MS) : 65536); }
      else if (v.cmd == "KEYS") { snprintf(e.keys, sizeof e.keys, "%s", a); e.k_idx = 0; e.k_prox = cyc; e.k_baixo = false; }
      else if (v.cmd == "SCR") ecra(a);
      else if (v.cmd == "SCRS") { e.scr_per = (long long)(atof(a) * CICLOS_MS); e.scr_prox = cyc; }
      else if (v.cmd == "MEM") memoria(a);
      else if (v.cmd == "SAVE") {
        VerilatedSave os; os.open(a);
        os << *t; os.write(&e, sizeof e); os.write(sdm, sizeof sdm); os.close();
        printf("%10.3f ms estado guardado em %s\n", ms, a);
      } else if (v.cmd == "FIM") { cyc = N; }
      else if (v.cmd == "TIROM") { size_t n = carrega(a, 0x080000, 4096); printf("%10.3f ms ROM do TI: %s (%zu bytes)\n", ms, a, n); }
      else if (v.cmd == "FDD" || v.cmd == "FDDP") {
        fdd_sem_rst = v.cmd == "FDDP";                                   // (2026-11-08) FDDP: como o plugin, o Timex so' no RST

        POE(gs_rst, 1); POE(fdd_on, 1); POE(f_disco, 1); POE(f_pausa, 0); POE(ti_ld, 0);
        size_t n = carrega(a, 0x400000, 0x200000);
        e.t_gsrst_fim = cyc + 1000;
        printf("%10.3f ms a FDD3000 ligada, com disco (%zu bytes de %s)\n", ms, n, a);
      } else if (v.cmd == "DISCO") {
        size_t n = carrega(a, 0x500000, 0x100000, 0x100000);
        POE(f_disco, 1);
        printf("%10.3f ms disco novo na FDD (%zu bytes de %s)\n", ms, n, a);
      } else if (v.cmd == "FDDRESET") { POE(gs_rst, 1); e.t_fddrst_fim = cyc + (*a ? (long long)(atof(a) * CICLOS_MS) : 5400); }
      else if (v.cmd == "SEMDISCO") POE(f_disco, 0);
      else printf("evento desconhecido: %s\n", v.cmd.c_str());
    }

    // ---- registos: a ligacao TI <-> FDD e a FDD
    uint8_t f2t = c->F_ti_o, t2f = c->R_ti2fdd, pag = c->R_ti_pag, nmis = c->R_nmi_s;
    uint8_t est = (c->R_fdd_on) | (c->R_f_disco << 1) | (c->R_f_pausa << 2) | (c->R_ti_ld << 3) | (c->R_gs_rst << 4);
    if (est != e.est_ant) printf("%10.3f ms fdd_on=%d disco=%d pausa=%d ti_ld=%d gs_rst=%d\n", ms, est & 1, (est >> 1) & 1,
                                 (est >> 2) & 1, (est >> 3) & 1, (est >> 4) & 1);
    if (nmis != e.nmi_ant) printf("%10.3f ms nmi_s = %d\n", ms, nmis);
    if (c->R_fdd_on && e.n_lig < 60) {
      if (pag != e.pag_ant) { printf("%10.3f ms TI %s (PC %04X)\n", ms, pag ? "entra" : "sai", pc_m1); e.n_lig++; }
      if (t2f != e.t2f_ant) { printf("%10.3f ms TI->FDD %02X\n", ms, t2f); e.n_lig++; }
      if (f2t != e.f2t_ant) { printf("%10.3f ms FDD->TI %02X\n", ms, f2t); e.n_lig++; }
    }
    e.f2t_ant = f2t; e.t2f_ant = t2f; e.pag_ant = pag; e.nmi_ant = nmis; e.est_ant = est;

    // ---- o PC dos dois Z80 (o endereco no M1) para a linha de estado
    if (!c->P_cpu_m1) pc_m1 = c->P_cpu_a;
    if (!c->P_gs_m1) pcf_m1 = c->P_gs_a;
    // ---- (2026-11-06) o teclado: em cada leitura do porto xxFE, o byte que o Z80 guardou (DI_Reg) no fim do ciclo de
    //      E/S. Uma tecla carregada com o mat a 0 (o banco nao carrega em nenhuma) e' uma tecla fantasma.
    if (!c->P_cpu_iorq && !c->P_cpu_rd && c->P_cpu_m1) { fe_a = c->P_cpu_a; fe_rd = true; }
    else if (fe_rd && c->P_cpu_iorq) {
      fe_rd = false;
      if ((fe_a & 0xFF) == 0xFE) {
        n_fe++;
        uint8_t v = c->P_cpu_di_reg;
        if ((v & 0x1F) != 0x1F && t->mat == 0) {
          static const char* nomes_k[8][5] = {{"CS","Z","X","C","V"}, {"A","S","D","F","G"}, {"Q","W","E","R","T"},
            {"1","2","3","4","5"}, {"0","9","8","7","6"}, {"P","O","I","U","Y"}, {"ENT","L","K","J","H"}, {"SPC","SS","M","N","B"}};
          if (++n_fant <= 60) {
            char k[200] = ""; size_t n = 0;
            for (int f = 0; f < 8; f++) if (!((fe_a >> (8 + f)) & 1))
              for (int b = 0; b < 5; b++) if (!((v >> b) & 1)) n += snprintf(k + n, sizeof k - n, " %s", nomes_k[f][b]);
            printf("%10.3f ms TECLA FANTASMA: IN (%04X) = %02X:%s (PC %04X)\n", ms, fe_a, v, k, pc_m1);
          }
        }
      }
    }
    // ---- (2026-11-08) o registo dos comandos do WD1770
    if (fcl && ms >= fc_i && ms <= fc_f) {
      int busy = c->F_busy & 1, face = c->F_face & 1, drv = c->F_drv0 & 1;
      if (face != face_ant || drv != drv_ant)
        fprintf(fcl, "%10.3f E0: face %d drive0 %d (FDD PC %04X)\n", ms, face, drv, (unsigned)c->P_gs_a);
      face_ant = face; drv_ant = drv;
      if (busy && !busy_ant)
        fprintf(fcl, "%10.3f inicio: tipo1 %d modo %d multi %d | pista(fis) %d reg.pista %d sector %d face %d (FDD PC %04X)\n",
                ms, c->F_tipo1 & 1, (int)c->F_modo, c->F_multi & 1, (int)c->F_fis, (int)c->F_r_trk, (int)c->F_r_sec, face,
                (unsigned)c->P_gs_a);
      if (!busy && busy_ant)
        fprintf(fcl, "%10.3f fim: rnf %d | fis %d reg.pista %d sector %d\n", ms, c->F_rnf & 1, (int)c->F_fis,
                (int)c->F_r_trk, (int)c->F_r_sec);
      busy_ant = busy;
    }
    // ---- (89) a luz da drive da FDD3000 (o core diz quando o controlador le' ou escreve)
    if (t->fdd_luz && !luz_ant) n_luz++;
    if (t->fdd_luz) luz_ms += 1.0 / 54000.0;
    luz_ant = t->fdd_luz;
    // ---- o traco dos saltos (o PC que nao segue o anterior) e das mudancas de modo
    if (tr && ms >= tr_i && ms <= tr_f) {
      uint8_t m1 = c->P_cpu_m1;
      if (!m1 && m1_ant) {
        uint16_t pc = c->P_cpu_a;
        if (pc < pc_ant || pc > pc_ant + 4) {
          if (pc == salto_para && pc_ant == salto_de) repete++;
          else {
            if (repete) fprintf(tr, "            ... x%ld\n", repete);
            repete = 0;
            fprintf(tr, "%10.4f %04X->%04X ti=%d\n", ms, pc_ant, pc, (int)pag);
            salto_de = pc_ant; salto_para = pc;
          }
        }
        pc_ant = pc;
      }
      m1_ant = m1;
      int mo = c->R_regff & 7, hc = t->hcor, f7 = c->__PVT__dv__DOT__bancos_128k__DOT__ff7, hs = c->__PVT__dv__DOT__bancos_128k__DOT__hsr;
      if (mo != mo_ant || hc != hc_ant || f7 != ff7_ant || hs != hsr_ant || pag != pag_tr) {
        fprintf(tr, "%10.4f MUDA modo=%d hcor=%d ff7=%d hsr=%02X ti=%d (PC %04X)\n", ms, mo, hc, f7, hs, (int)pag, pc_ant);
        mo_ant = mo; hc_ant = hc; ff7_ant = f7; hsr_ant = hs; pag_tr = pag;
      }
    }
    if (tr && ms > tr_f) { if (repete) fprintf(tr, "            ... x%ld\n", repete); fclose(tr); tr = nullptr; }
    if (trf && ms >= trf_i && ms <= trf_f) {
      uint8_t m1 = c->P_gs_m1;
      if (!m1 && m1f_ant) {
        uint16_t pc = c->P_gs_a;
        if (pc < pcf_ant || pc > pcf_ant + 4) {
          if (pc == saltof_para && pcf_ant == saltof_de) repetef++;
          else {
            if (repetef) fprintf(trf, "            ... x%ld\n", repetef);
            repetef = 0;
            fprintf(trf, "%10.4f %04X->%04X\n", ms, pcf_ant, pc);
            saltof_de = pcf_ant; saltof_para = pc;
          }
        }
        pcf_ant = pc;
      }
      m1f_ant = m1;
    }
    if (trf && ms > trf_f) { if (repetef) fprintf(trf, "            ... x%ld\n", repetef); fclose(trf); trf = nullptr; }

    // ---- a linha de estado
    if (cyc >= prox_est) {
      prox_est += EST_C;
      printf("%10.3f ms PC=%04X FDD PC=%04X ti=%d EF:%02X/%02X border=%d FF=%02X hsr=%02X ff7=%d SD: %ld cmd %ld CMD17 %ld blocos CMD18 %ld CMD24\n",
             ms, pc_m1, pcf_m1, pag, f2t, t2f, t->border, (unsigned)c->R_regff,
             (unsigned)c->__PVT__dv__DOT__bancos_128k__DOT__hsr, (int)c->__PVT__dv__DOT__bancos_128k__DOT__ff7,
             s.ncmds, s.n17, s.n18, s.n24);
      printf("%10.3f ms teclado: %ld leituras do FE, %ld com tecla fantasma; luz da drive: %ld acessos, %.2f ms acesa\n",
             ms, n_fe, n_fant, n_luz, luz_ms);
      fflush(stdout);
    }
  }
  if (tr) fclose(tr);
  if (trf) fclose(trf);
  ecra("ecra_fim");
  printf("%10.3f ms fim\n", e.cyc / (double)CICLOS_MS);
  t->final();
  fclose(sdf);
  return 0;
}
