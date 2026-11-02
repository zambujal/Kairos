-- fita_sd.vhd - (78) a fita na SDRAM: o TZX sem o ESP.
-- O plugin TZX (Z80) converte o ficheiro para uma lista de palavras de 16 bits (little-endian) e escreve-a
-- na SDRAM em 080000h-0FFFFFh (512 KB, livres) (ZXUNO A7h, um byte de cada vez, o endereco avanca sozinho). Depois liga a
-- fita (A6h = 1) e o core manda os impulsos para a cassete (a mesma fila do ESP) enquanto o jogo carrega.
--   ZXUNO A6h, escrita: bit 0 = 1 toca desde o principio; 0 = para (esvazia a cassete); bit 1 = 1 poe o endereco
--                       de escrita no principio (antes de escrever a lista)
--   ZXUNO A6h ou A7h, leitura: bit 0 = a tocar, bit 1 = acabou (chegou ao FFFFh), bit 2 = o ultimo byte
--                       escrito ainda nao foi para a SDRAM (esperar antes do seguinte)
--   ZXUNO A7h, escrita: o byte seguinte da lista
-- Palavras da lista:
--   0000h-EFFFh  vao para a cassete como estao (impulso, pausa, nivel: ver cassete.vhd)
--   F001h L N    N impulsos de L T (o tom guia)
--   F002h B0 B1 N U  dados: N bytes (1-65535; um bloco maior vai em varios seguidos), bits de 0 com B0 T, de 1 com B1 T (dois impulsos por bit, o
--                bit 7 primeiro); U = bits usados no ultimo byte (1-8); depois os bytes, 2 por palavra
--                (o 1.o no byte baixo), a acabar numa palavra inteira
--   FFFFh        o fim
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fita_sd is
  port (
    clk     : in  std_logic;
    -- o Z80 (os registos ZXUNO)
    ctl_wr  : in  std_logic;                      -- 1 ciclo: escrita no A6h
    dat_wr  : in  std_logic;                      -- 1 ciclo: escrita no A7h
    d       : in  std_logic_vector(7 downto 0);
    estado  : out std_logic_vector(7 downto 0);
    -- a SDRAM (pedido ate' ack; a leitura devolve a palavra de 32 bits em rq com rq_v)
    s_req   : out std_logic;
    s_we    : out std_logic;
    s_a     : out std_logic_vector(22 downto 0);
    s_d     : out std_logic_vector(7 downto 0);
    s_ack   : in  std_logic;                      -- o pedido foi aceite
    rq      : in  std_logic_vector(31 downto 0);
    rq_v    : in  std_logic;                      -- a leitura chegou
    -- a cassete
    c_wr    : out std_logic;
    c_d     : out std_logic_vector(15 downto 0);
    c_limpa : out std_logic;
    c_livres: in  std_logic_vector(7 downto 0);
    c_ativa : in  std_logic := '0';               -- (79) a cassete ainda a tocar (no fim: para sozinha quando esvazia)
    ativa   : out std_logic                       -- 1 = a fita e' nossa (a tocar)
  );
end entity;

architecture rtl of fita_sd is
  constant BASE : unsigned(22 downto 0) := to_unsigned(16#080000#, 23);
  signal toca, acabou : std_logic := '0';
  signal wa : unsigned(18 downto 0) := (others => '0');    -- o endereco de escrita (byte, desde BASE)
  signal ra : unsigned(16 downto 0) := (others => '0');    -- a palavra de 32 bits seguinte a ler (desde BASE)
  signal w_pend, r_pend, r_voo : std_logic := '0';
  signal w_byte : std_logic_vector(7 downto 0) := (others => '0');
  -- as palavras de 16 bits lidas: buf guarda a 2.a metade
  signal buf : std_logic_vector(15 downto 0) := (others => '0');
  signal buf_ok, pal_ok : std_logic := '0';
  signal pal : std_logic_vector(15 downto 0) := (others => '0');
  type est_t is (E_CMD, E_REP_L, E_REP_N, E_REP, E_D_B0, E_D_B1, E_D_N, E_D_U, E_D_PAL, E_D_BIT, E_FIM);
  signal e : est_t := E_CMD;
  signal rep_l : std_logic_vector(14 downto 0) := (others => '0');
  signal rep_n : unsigned(15 downto 0) := (others => '0');
  signal b0, b1 : std_logic_vector(14 downto 0) := (others => '0');
  signal nb : unsigned(15 downto 0) := (others => '0');     -- bytes que faltam
  signal ult : unsigned(3 downto 0) := (others => '0');     -- bits usados no ultimo byte
  signal par : std_logic_vector(15 downto 0) := (others => '0');   -- os 2 bytes da palavra de dados
  signal meio : std_logic := '0';                           -- 0 = o byte baixo da palavra, 1 = o alto
  signal byte : std_logic_vector(7 downto 0) := (others => '0');
  signal nbit : unsigned(3 downto 0) := (others => '0');    -- bits que faltam do byte
  signal seg : std_logic := '0';                            -- o 2.o impulso do bit
  signal cwr : std_logic := '0';
  signal cd : std_logic_vector(15 downto 0) := (others => '0');
  signal limpa_r : std_logic := '0';
  signal cabe : std_logic;
begin
  estado <= "00000" & w_pend & acabou & toca;
  ativa <= toca;
  c_wr <= cwr; c_d <= cd; c_limpa <= limpa_r;
  cabe <= '1' when unsigned(c_livres) > 4 and cwr = '0' else '0';
  s_req <= w_pend or r_pend;
  s_we  <= w_pend;
  s_a   <= std_logic_vector(BASE + resize(wa, 23)) when w_pend = '1' else std_logic_vector(BASE + resize(ra & "00", 23));
  s_d   <= w_byte;

  process(clk)
    variable usa : std_logic;                   -- esta volta consumiu a palavra pal
  begin
    if rising_edge(clk) then
      cwr <= '0'; limpa_r <= '0'; usa := '0';
      -- o Z80
      if ctl_wr = '1' then
        if d(1) = '1' then wa <= (others => '0'); end if;
        if d(0) = '1' then
          toca <= '1'; acabou <= '0'; ra <= (others => '0'); buf_ok <= '0'; pal_ok <= '0'; e <= E_CMD;
          r_pend <= '0'; r_voo <= '0';
        else
          toca <= '0'; limpa_r <= '1';
        end if;
      end if;
      if dat_wr = '1' then w_byte <= d; w_pend <= '1'; end if;
      if s_ack = '1' then
        if w_pend = '1' then w_pend <= '0'; wa <= wa + 1;
        else r_pend <= '0'; r_voo <= '1'; end if;
      end if;
      -- a leitura: uma palavra de 32 bits de cada vez, quando a de 16 seguinte faz falta
      if rq_v = '1' and r_voo = '1' then
        r_voo <= '0'; ra <= ra + 1;
        pal <= rq(15 downto 0); pal_ok <= '1'; buf <= rq(31 downto 16); buf_ok <= '1';
      end if;
      if toca = '1' and pal_ok = '0' and r_pend = '0' and r_voo = '0' and w_pend = '0' and ctl_wr = '0' then
        if buf_ok = '1' then pal <= buf; pal_ok <= '1'; buf_ok <= '0';
        else r_pend <= '1'; end if;
      end if;
      -- a maquina: consome as palavras e manda os impulsos
      if toca = '1' and ctl_wr = '0' then
        case e is
          when E_CMD =>
            if pal_ok = '1' then
              if pal = x"FFFF" then e <= E_FIM; usa := '1';
              elsif pal = x"F001" then e <= E_REP_L; usa := '1';
              elsif pal = x"F002" then e <= E_D_B0; usa := '1';
              elsif cabe = '1' then
                if pal(15 downto 12) /= x"F" then cd <= pal; cwr <= '1'; end if;   -- (outros Fxxx: ignorados)
                usa := '1';
              end if;
            end if;
          when E_REP_L => if pal_ok = '1' then rep_l <= pal(14 downto 0); e <= E_REP_N; usa := '1'; end if;
          when E_REP_N => if pal_ok = '1' then rep_n <= unsigned(pal); e <= E_REP; usa := '1'; end if;
          when E_REP =>
            if rep_n = 0 then e <= E_CMD;
            elsif cabe = '1' then cd <= '0' & rep_l; cwr <= '1'; rep_n <= rep_n - 1; end if;
          when E_D_B0 => if pal_ok = '1' then b0 <= pal(14 downto 0); e <= E_D_B1; usa := '1'; end if;
          when E_D_B1 => if pal_ok = '1' then b1 <= pal(14 downto 0); e <= E_D_N; usa := '1'; end if;
          when E_D_N  => if pal_ok = '1' then nb <= unsigned(pal); e <= E_D_U; usa := '1'; end if;
          when E_D_U =>
            if pal_ok = '1' then
              ult <= unsigned(pal(3 downto 0)); usa := '1'; meio <= '0';
              if nb = 0 then e <= E_CMD; else e <= E_D_PAL; end if;
            end if;
          when E_D_PAL =>                         -- o byte seguinte (da palavra que ja' esta' em par, ou de uma nova)
            if nb = 0 then
              e <= E_CMD;
            elsif meio = '1' then
              byte <= par(15 downto 8); meio <= '0'; seg <= '0'; e <= E_D_BIT;
              if nb = 1 then nbit <= ult; else nbit <= to_unsigned(8, 4); end if;
              nb <= nb - 1;
            elsif pal_ok = '1' then
              par <= pal; usa := '1';
              byte <= pal(7 downto 0); meio <= '1'; seg <= '0'; e <= E_D_BIT;
              if nb = 1 then nbit <= ult; else nbit <= to_unsigned(8, 4); end if;
              nb <= nb - 1;
            end if;
          when E_D_BIT =>
            if nbit = 0 then
              if nb = 0 then e <= E_CMD; meio <= '0'; else e <= E_D_PAL; end if;
            elsif cabe = '1' then
              if byte(7) = '1' then cd <= '0' & b1; else cd <= '0' & b0; end if;
              cwr <= '1';
              if seg = '1' then seg <= '0'; byte <= byte(6 downto 0) & '0'; nbit <= nbit - 1; else seg <= '1'; end if;
            end if;
          when E_FIM =>                           -- (79) a lista acabou: quando a cassete esvaziar, para (o Z80 volta
            acabou <= '1';                        -- a' velocidade dele e a cassete volta a ser do ESP)
            if c_ativa = '0' and cwr = '0' then toca <= '0'; end if;
        end case;
      end if;
      if usa = '1' then pal_ok <= '0'; end if;
    end if;
  end process;
end architecture;
