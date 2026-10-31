-- ponte_rapida.vhd - teste da ponte rapida (2026-10-24): os dados do ESP apanhados com o proprio relogio
-- do ESP (e nao amostrados a 54 MHz). Comandos (octal, modo 0, comando e endereco num ciclo cada):
--   03h escrever: os bytes seguintes devem ser uma sequencia LFSR (seguinte = f(anterior)): conta os bytes
--       e os que nao seguem a sequencia
--   04h ler: 2 ciclos de espera; a FPGA manda a sequencia LFSR (o ESP verifica-a), muda no flanco de descida
--   06h ler como o 04h, mas a FPGA muda os dados no flanco de SUBIDA (2026-10-24: escolher o melhor)
--   05h sair: a ponte normal volta a ouvir (ver o registo 5F da ponte_esp)
--   07h (2026-10-24) escrita em bloco: os bytes vao para uma fila de 2 KB (do relogio do ESP para os 54 MHz);
--       a ponte_esp tira-os de la' para a fila normal (SDRAM, RAM de video ou cartao, registo 39)
--   08h teste como o 03h, mas a FPGA le' os dados no flanco de DESCIDA (para os 40 MHz)
-- f(x) = (x >> 1) xor (B8h se x(0) = 1): periodo 255 (nunca 0).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ponte_rapida is
  port (
    sclk   : in  std_logic;
    cs     : in  std_logic;                       -- 1 = sem transaccao
    d      : in  std_logic_vector(7 downto 0);
    q      : out std_logic_vector(7 downto 0);
    oe     : out std_logic;
    sair_t : out std_logic;                       -- muda a cada comando 05h
    wb     : out std_logic_vector(23 downto 0);   -- bytes escritos (03h)
    we     : out std_logic_vector(15 downto 0);   -- bytes fora da sequencia
    rb     : out std_logic_vector(23 downto 0);   -- bytes lidos (04h/06h)
    -- fila de 2 KB do 07h, lado dos 54 MHz
    clk    : in  std_logic;
    tira   : in  std_logic;                       -- 1 ciclo: tira um byte (so' sem vazia)
    b_q    : out std_logic_vector(7 downto 0);    -- o byte tirado, no ciclo seguinte (com b_ok = 1)
    b_ok   : out std_logic;
    b_vazia: out std_logic;
    b_livres : out std_logic_vector(11 downto 0); -- lugares livres (0-2048)
    b_vis  : out std_logic                        -- muda a cada comando 07h (para a ponte_esp deixar de estar surda)
  );
end entity;

architecture rtl of ponte_rapida is
  -- (69) so' o 07h (escrita em bloco) e o 05h: os testes 03h/04h/06h/08h e os contadores sairam (o ESP nao os usa;
  -- faltava lugar na FPGA). Os portos wb/we/rb ficam a 0 e a FPGA nunca conduz (oe = 0).
  signal k : unsigned(2 downto 0) := (others => '0');
  signal cmd : std_logic_vector(7 downto 0) := (others => '0');
  signal sair_r : std_logic := '0';
  -- fila do 07h
  type fila_t is array (0 to 2047) of std_logic_vector(7 downto 0);
  signal fila : fila_t;
  signal bwp, brp, bwp_s : unsigned(11 downto 0) := (others => '0');
  signal bwg, bwg1, bwg2 : std_logic_vector(11 downto 0) := (others => '0');
  signal b_q_r : std_logic_vector(7 downto 0) := (others => '0');
  signal b_ok_r, vis_r : std_logic := '0';
  function g2b(g : std_logic_vector(11 downto 0)) return unsigned is
    variable b : std_logic_vector(11 downto 0);
  begin
    b(11) := g(11);
    for i in 10 downto 0 loop b(i) := b(i + 1) xor g(i); end loop;
    return unsigned(b);
  end function;
begin
  sair_t <= sair_r; wb <= (others => '0'); we <= (others => '0'); rb <= (others => '0');
  oe <= '0'; q <= (others => '0');

  process(sclk, cs)
  begin
    if cs = '1' then
      k <= (others => '0');
    elsif rising_edge(sclk) then
      if k /= 7 then k <= k + 1; end if;
      if k = 0 then cmd <= d;
      elsif k = 1 then
        if cmd = x"05" then sair_r <= not sair_r; end if;
        if cmd = x"07" then vis_r <= not vis_r; end if;
      end if;
    end if;
  end process;

  -- 07h: os dados para a fila (no relogio do ESP; o ponteiro passa para os 54 MHz em codigo Gray)
  process(sclk)
    variable n : unsigned(11 downto 0);
  begin
    if rising_edge(sclk) then
      if cs = '0' and cmd = x"07" and k >= 2 then
        fila(to_integer(bwp(10 downto 0))) <= d;
        n := bwp + 1; bwp <= n;
        bwg <= std_logic_vector(n xor ('0' & n(11 downto 1)));
      end if;
    end if;
  end process;
  process(clk)
  begin
    if rising_edge(clk) then
      bwg1 <= bwg; bwg2 <= bwg1; bwp_s <= g2b(bwg2);
      b_ok_r <= '0';
      if tira = '1' and bwp_s /= brp then
        b_q_r <= fila(to_integer(brp(10 downto 0))); b_ok_r <= '1'; brp <= brp + 1;
      end if;
    end if;
  end process;
  b_q <= b_q_r; b_ok <= b_ok_r; b_vis <= vis_r;
  b_vazia <= '1' when bwp_s = brp else '0';
  b_livres <= std_logic_vector(to_unsigned(2048, 12) - (bwp_s - brp));
end architecture;
