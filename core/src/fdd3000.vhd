-- fdd3000.vhd: (87) os portos da Timex FDD3000 para o Z80 do General Sound em modo FDD (core Kairos).
--
--   A FDD3000 e' um segundo computador (Z80, WD1770, 64K de RAM). No Kairos o Z80 e' o do General Sound
--   (com o GS desligado) e o disco esta' todo na SDRAM: o WD1770 daqui le' e escreve os sectores la',
--   pela mesma ligacao a' memoria do Z80 (no ciclo de E/S do porto de dados).
--
--   Portos do lado da FDD (como o fdd3000e de slawkis, no Fuse; A7-A5):
--     001 (20h-3Fh)  escrita: o byte para o Timex Interface (o IN EF do Timex)
--                    leitura: bit 7 = DRQ do WD1770 OU bit 7 do TI; bits 6-0 = o que o Timex escreveu no EF
--     110 (C0h-C3h)  WD1770: 0 comando / estado, 1 pista, 2 sector, 3 dados
--     111 (E0h-FFh)  controlo (escrita): bit 6 = 0 -> ROM de arranque em 0000-07FF; bit 4 = 0 -> face 1;
--                    bits 3-0 = 0 -> drive 3-0 escolhida (so' a drive 0 tem disco)
--     outros: leitura FFh
--   Disco na SDRAM: 80 pistas x 2 faces x 16 sectores de 256 bytes (o TOS): o byte b do sector s da pista p,
--   face f, esta' em ((p*2 + f)*16 + s)*256 + b (20 bits). Sectores de 0 a 15 (o arranque le' o sector 0).
--   O WD1770 aqui: Restore, Seek, Step/Step-in/Step-out, Read/Write Sector (tambem varios), Read Address,
--   Read/Write Track (acabam logo: a formatacao nao apaga o disco), Force Interrupt. Sem tempos reais:
--   os comandos acabam logo (o Tipo I ao fim de ~1,2 ms: com ~1 us a FDD lia o estado ja' sem busy, apagava o INTRQ
--   e ficava a' espera da interrupcao; o Seek da pista 3 falhava e o jogo ia para o (c) Sinclair). INTRQ vai ao INT do Z80.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fdd3000 is
  generic (CLK_HZ : integer := 54000000);
  port (
    clk     : in  std_logic;
    reset_n : in  std_logic;
    a       : in  std_logic_vector(7 downto 0);   -- A7-A0 do Z80 da FDD
    d       : in  std_logic_vector(7 downto 0);   -- dado do Z80 (OUT)
    iorq_n, rd_n, wr_n, m1_n : in std_logic;
    q       : out std_logic_vector(7 downto 0);   -- dado para o Z80 (IN), sem o do disco
    q_mem   : out std_logic;                      -- 1 = este IN e' o porto de dados a ler o disco (o dado vem da memoria)
    -- o disco na SDRAM (pela memoria do Z80)
    m_rd    : out std_logic;                      -- 1 = este IN le' o byte do disco em m_ad
    m_wr    : out std_logic;                      -- 1 = este OUT escreve o byte no disco em m_ad
    m_ad    : out unsigned(19 downto 0);
    -- o Timex Interface
    ti_in   : in  std_logic_vector(7 downto 0);   -- o que o Timex escreveu no EF
    disco   : in  std_logic := '1';               -- (88) 0 = drive sem disco: as leituras dao RNF (o arranque da FDD fica a' espera)
    ti_out  : out std_logic_vector(7 downto 0);   -- o que o Timex le' no EF
    paged   : out std_logic;                      -- 1 = ROM de arranque em 0000-07FF
    intrq   : out std_logic;
    ativa   : out std_logic                       -- (89) o WD1770 ocupado (a luz da drive)
  );
end entity;

architecture rtl of fdd3000 is
  signal ti_o : std_logic_vector(7 downto 0) := (others => '0');
  signal pg, face, drv0 : std_logic := '1';
  signal r_trk, r_sec, r_dat : unsigned(7 downto 0) := (others => '0');
  signal fis : unsigned(6 downto 0) := (others => '0');    -- a pista onde a cabeca esta'
  signal dir_in : std_logic := '1';
  signal busy, drq, irq, rnf, tipo1 : std_logic := '0';
  -- modo: 0 nada, 1 ler sector, 2 escrever sector, 3 ler endereco
  signal modo : integer range 0 to 3 := 0;
  signal multi : std_logic := '0';
  signal cnt : unsigned(8 downto 0) := (others => '0');
  signal t1 : unsigned(15 downto 0) := (others => '0');     -- (87g) o fim do Tipo I (~1,2 ms): o TOS le' o estado antes do fim
  signal idx_c : unsigned(23 downto 0) := (others => '0');  -- (87d) o furo do indice: ~310 ms a 54 MHz, ~5 ms
  signal idx : std_logic := '0';
  signal io_d : std_logic := '0';
  signal pa_d : std_logic_vector(7 downto 0) := (others => '0');
  signal io, io_rd, io_wr : std_logic;
  signal grp : std_logic_vector(2 downto 0);
  signal dados : std_logic;
  signal st : std_logic_vector(7 downto 0);
  signal ra : std_logic_vector(7 downto 0);
  signal trk0 : std_logic;
begin
  io    <= '1' when iorq_n = '0' and m1_n = '1' else '0';
  io_rd <= io and not rd_n;
  io_wr <= io and not wr_n;
  grp   <= a(7 downto 5);
  dados <= '1' when grp = "110" and a(1 downto 0) = "11" else '0';

  trk0 <= '1' when fis = 0 else '0';
  st <= '1' & '0' & '1' & '0' & '0' & (drv0 and trk0) & (drv0 and idx) & busy when tipo1 = '1' else
        '1' & '0' & '0' & rnf & '0' & '0' & drq & busy;

  -- Read Address: pista, face, sector, tamanho (1 = 256), CRC (2)
  with to_integer(cnt(2 downto 0)) select ra <=
    '0' & std_logic_vector(fis) when 0,
    "0000000" & face             when 1,
    std_logic_vector(r_sec)      when 2,
    x"01"                        when 3,
    x"00"                        when others;

  q <= (drq or ti_in(7)) & ti_in(6 downto 0) when grp = "001" else
       st                                     when grp = "110" and a(1 downto 0) = "00" else
       std_logic_vector(r_trk)                when grp = "110" and a(1 downto 0) = "01" else
       std_logic_vector(r_sec)                when grp = "110" and a(1 downto 0) = "10" else
       ra                                     when dados = '1' and modo = 3 else
       std_logic_vector(r_dat)                when dados = '1' else
       x"FF";
  q_mem <= '1' when dados = '1' and modo = 1 and busy = '1' else '0';
  m_rd  <= io_rd when dados = '1' and modo = 1 and busy = '1' else '0';
  m_wr  <= io_wr when dados = '1' and modo = 2 and busy = '1' else '0';
  m_ad  <= fis & face & r_sec(3 downto 0) & cnt(7 downto 0);

  ti_out <= ti_o;
  paged  <= pg;
  intrq  <= irq;
  ativa  <= busy;

  process(clk)
    variable fim : std_logic;
  begin
    if rising_edge(clk) then
      -- o furo do indice
      idx_c <= idx_c + 1;
      if idx_c(23 downto 18) = 0 then idx <= '1'; else idx <= '0'; end if;

      io_d <= io;
      if io = '1' then pa_d <= a; end if;
      if reset_n = '0' then
        ti_o <= (others => '0'); pg <= '1'; face <= '0'; drv0 <= '1';
        r_trk <= (others => '0'); r_sec <= (others => '0'); r_dat <= (others => '0');
        fis <= (others => '0'); busy <= '0'; drq <= '0'; irq <= '0'; rnf <= '0'; tipo1 <= '1';
        modo <= 0; t1 <= (others => '0');
      else
        if t1 /= 0 then
          t1 <= t1 - 1;
          if t1 = 1 then busy <= '0'; irq <= '1'; end if;
        end if;
        -- inicio de um IN / OUT (uma vez por ciclo de E/S)
        if io = '1' and io_d = '0' then
          if rd_n = '0' and grp = "110" and a(1 downto 0) = "00" then irq <= '0'; end if;   -- ler o estado limpa o INTRQ
          if wr_n = '0' then
            case grp is
              when "001" => ti_o <= d;
              when "111" => pg <= not d(6); face <= not d(4); drv0 <= not d(0);
              when "110" =>
                case a(1 downto 0) is
                  when "00" =>                                   -- comando
                    if d(7 downto 4) = "1101" then               -- Force Interrupt
                      modo <= 0; busy <= '0'; drq <= '0'; t1 <= (others => '0');
                      if d(3 downto 0) /= "0000" then irq <= '1'; else irq <= '0'; end if;
                    elsif busy = '0' then
                      irq <= '0'; rnf <= '0'; cnt <= (others => '0'); multi <= d(4);
                      if d(7) = '0' then                         -- Tipo I
                        tipo1 <= '1'; busy <= '1'; t1 <= (others => '1');
                        case d(7 downto 5) is
                          when "000" =>
                            if d(4) = '0' then fis <= (others => '0'); r_trk <= (others => '0');   -- Restore
                            else                                                             -- Seek
                              if r_dat < 84 then fis <= r_dat(6 downto 0); else fis <= to_unsigned(83, 7); end if;
                              r_trk <= r_dat;
                            end if;
                          when others =>                         -- Step (001), Step-in (010), Step-out (011)
                            if d(6 downto 5) = "10" or (d(6 downto 5) = "01" and dir_in = '1') then
                              dir_in <= '1';
                              if fis < 83 then fis <= fis + 1; end if;
                              if d(4) = '1' then r_trk <= r_trk + 1; end if;
                            else
                              dir_in <= '0';
                              if fis > 0 then fis <= fis - 1; end if;
                              if d(4) = '1' then r_trk <= r_trk - 1; end if;
                            end if;
                        end case;
                      else                                       -- Tipo II e III
                        tipo1 <= '0';
                        if d(7 downto 5) = "100" or d(7 downto 5) = "101" then
                          if drv0 = '0' or r_sec > 15 or disco = '0' then rnf <= '1'; irq <= '1';   -- sem disco / sem esse sector
                          else
                            busy <= '1'; drq <= '1';
                            if d(5) = '0' then modo <= 1; else modo <= 2; end if;
                          end if;
                        elsif d(7 downto 4) = "1100" then busy <= '1'; drq <= '1'; modo <= 3;   -- Read Address
                        else irq <= '1';                       -- (87d) Read / Write Track: acabam logo
                        end if;
                      end if;
                    end if;
                  when "01" => r_trk <= unsigned(d);
                  when "10" => r_sec <= unsigned(d);
                  when others => r_dat <= unsigned(d);
                end case;
              when others => null;
            end case;
          end if;
        end if;
        -- fim de um IN / OUT no porto de dados: o byte seguinte
        if io = '0' and io_d = '1' and pa_d(7 downto 5) = "110" and pa_d(1 downto 0) = "11" and busy = '1' and modo /= 0 then
          fim := '0';
          cnt <= cnt + 1;
          case modo is
            when 1 | 2 =>
              if cnt(7 downto 0) = 255 then
                if multi = '1' and r_sec < 15 then r_sec <= r_sec + 1; cnt <= (others => '0');
                else
                  if multi = '1' then rnf <= '1'; end if;          -- o WD acaba os varios sectores com RNF
                  fim := '1';
                end if;
              end if;
            when others => if cnt = 5 then fim := '1'; end if;
          end case;
          if fim = '1' then modo <= 0; busy <= '0'; drq <= '0'; irq <= '1'; end if;
        end if;
      end if;
    end if;
  end process;
end architecture;
