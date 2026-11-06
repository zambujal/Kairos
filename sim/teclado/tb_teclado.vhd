-- tb_teclado.vhd: o caminho do teclado USB do Kairos (mcu_spi + hid_teclado), com o BL616 a falar como o FPGA-Companion
-- (SPI modo 1, ~26,7 MHz, CSN por GPIO). Mensagens: tecla carregada 01 01 kk kk [PS/2], largada 01 01 (80+kk) kk [F0 PS/2],
-- modificadores 68h+bit, rato (01 02 ...), joystick (01 03 ...), estado do SYS (00 00 ...). Verifica a matriz depois de
-- cada mensagem. A fase entre o SCLK e o clk54 varia de mensagem para mensagem.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_teclado is
  generic (DELTA_NS : integer := 1000;     -- do ultimo flanco do SCLK ao CSN a 1 (ns)
           SCLK_PS  : integer := 37500);   -- periodo do SCLK (ps): 26,67 MHz
end entity;

architecture sim of tb_teclado is
  signal clk : std_logic := '0';
  signal ss, sclk, mosi : std_logic := '1';
  signal miso, sys_stb, hid_stb, inicio : std_logic;
  signal dado, sys_q, hid_q : std_logic_vector(7 downto 0);
  signal mat : std_logic_vector(39 downto 0);
  signal f11, cad, cadn, alt : std_logic;
  signal rx, ry, joy : std_logic_vector(7 downto 0);
  signal rb : std_logic_vector(2 downto 0);
  signal rw : std_logic_vector(3 downto 0);
  signal atalho : std_logic_vector(21 downto 0);
  signal jcru : std_logic_vector(31 downto 0);
  signal fim : boolean := false;
  type bytes_t is array (natural range <>) of std_logic_vector(7 downto 0);
  constant DELTA_CS : time := DELTA_NS * 1 ns;
  constant T_SCLK : time := SCLK_PS * 1 ps;
begin
  clk <= not clk after 9.259 ns when not fim;    -- 54 MHz
  sclk_idle: process begin wait; end process;
  dut: entity work.mcu_spi port map (clk => clk, ss => ss, sclk => sclk, mosi => mosi, miso => miso,
      sys_stb => sys_stb, hid_stb => hid_stb, inicio => inicio, dado => dado, sys_q => sys_q, hid_q => hid_q);
  sys_q <= x"00";
  hid: entity work.hid_teclado port map (clk => clk, reset => '0', stb => hid_stb, inicio => inicio, d => dado,
      q => hid_q, mat => mat, f11 => f11, cad => cad, cadn => cadn, rato_x => rx, rato_y => ry, rato_b => rb,
      rato_w => rw, joy => joy, atalho => atalho, alt => alt, jcru => jcru);

  process
    variable n_err, n_msg : integer := 0;
    variable fase : time := 0 ns;
    procedure byte_spi(b : std_logic_vector(7 downto 0); ultimo : boolean) is
    begin
      for i in 7 downto 0 loop
        sclk <= '1'; mosi <= b(i);           -- modo 1: o mestre muda o dado na subida
        wait for T_SCLK / 2;
        sclk <= '0';                         -- e a FPGA le' na descida
        if not (ultimo and i = 0) then wait for T_SCLK / 2; end if;   -- no ultimo bit o DELTA conta desde a descida
      end loop;
    end procedure;
    procedure msg(m : bytes_t) is
    begin
      fase := fase + 3.7 ns; if fase > 18 ns then fase := fase - 18 ns; end if;
      wait for 2 us + fase;                  -- a fase do SCLK em relacao ao clk54 muda
      ss <= '0'; wait for 100 ns;
      for i in m'range loop
        byte_spi(m(i), i = m'high);
        if i /= m'high then wait for 150 ns; end if;   -- o poll_send de byte a byte
      end loop;
      wait for DELTA_CS;
      ss <= '1';
      wait for 1 us;
      n_msg := n_msg + 1;
    end procedure;
    procedure ve(bit_n : integer; v : std_logic; o_que : string) is
    begin
      if mat(bit_n) /= v then
        report "ERRO: " & o_que & ": mat(" & integer'image(bit_n) & ") = " & std_logic'image(mat(bit_n)) severity error;
        n_err := n_err + 1;
      end if;
    end procedure;
    procedure nada(o_que : string) is
    begin
      if mat /= (mat'range => '0') then
        report "ERRO: " & o_que & ": matriz nao esta' vazia" severity error;
        n_err := n_err + 1;
      end if;
    end procedure;
  begin
    wait for 1 us;
    -- o arranque do Companion: estado do SYS, IRQ, origem
    msg((x"00", x"00", x"00", x"00", x"00"));
    msg((x"00", x"05", x"01"));
    msg((x"00", x"06", x"00"));
    nada("depois do SYS");
    for rep in 1 to 20 loop
      -- o 2 (HID 1Fh, PS/2 1Eh)
      msg((x"01", x"01", x"1F", x"1F", x"1E"));           ve(16, '1', "2 carregado");
      msg((x"01", x"01", x"9F", x"1F", x"F0", x"1E"));    ve(16, '0', "2 largado"); nada("2 largado");
      -- o 1 e o 3 (ao lado)
      msg((x"01", x"01", x"1E", x"1E", x"16"));           ve(15, '1', "1 carregado"); ve(16, '0', "1 carregado (o 2 nao)");
      msg((x"01", x"01", x"9E", x"1E", x"F0", x"16"));    nada("1 largado");
      msg((x"01", x"01", x"20", x"20", x"26"));           ve(17, '1', "3 carregado"); ve(16, '0', "3 carregado (o 2 nao)");
      msg((x"01", x"01", x"A0", x"20", x"F0", x"26"));    nada("3 largado");
      -- Shift esquerdo (modificador 1: 68h+1), a letra A, larga tudo
      msg((x"01", x"01", x"69", x"01", x"12"));           ve(0, '1', "Shift");
      msg((x"01", x"01", x"04", x"04", x"1C"));           ve(5, '1', "A");
      msg((x"01", x"01", x"84", x"04", x"F0", x"1C"));
      msg((x"01", x"01", x"E9", x"01", x"F0", x"12"));    nada("Shift e A largados");
      -- o rato e o joystick nao mexem na matriz
      msg((x"01", x"02", x"00", x"05", x"FB", x"00"));    nada("rato");
      msg((x"01", x"03", x"00", x"02", x"80", x"7F", x"00")); nada("joystick");
      msg((x"01", x"03", x"00", x"00", x"80", x"80", x"00")); nada("joystick largado");
      -- o SYS no meio
      msg((x"00", x"03", x"00"));                          nada("SYS botoes");
    end loop;
    report "mensagens: " & integer'image(n_msg) & ", erros: " & integer'image(n_err) severity note;
    fim <= true;
    finish;
  end process;
end architecture;
