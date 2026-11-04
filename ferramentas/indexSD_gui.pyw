#!/usr/bin/env python3
# indexSD_gui.pyw - janela para fazer os indices do navegador do Kairos (_NAV) num cartao SD.
# Windows: dois cliques (precisa do Python 3 de www.python.org, que ja' traz o tkinter).
# Linux:   python3 indexSD_gui.pyw   (Fedora: sudo dnf install python3-tkinter;
#                                     Debian/Ubuntu: sudo apt install python3-tk)
# Usa o cartao.py (importado: o executavel feito com o PyInstaller ja' o leva dentro).
# O config.ini (barra das pastas, navegador normal) le'-se ao lado do programa ou na raiz do cartao.
import os, sys, string, threading, queue, contextlib
import tkinter as tk
from tkinter import ttk, filedialog, messagebox

# a pasta do programa: a do .exe/executavel (PyInstaller) ou a do .pyw
AQUI = os.path.dirname(os.path.abspath(sys.executable if getattr(sys, 'frozen', False) else __file__))
if AQUI not in sys.path: sys.path.insert(0, AQUI)
import cartao
SISTEMA = {'BIN', 'SYS', 'TMP', 'SYSTEM VOLUME INFORMATION', '_NAV'}


def cartoes():
    """[(caminho, texto)] dos cartoes/discos que se veem; os que tem BIN e SYS (esxDOS) primeiro"""
    sitios = []
    if os.name == 'nt':
        import ctypes
        mask = ctypes.windll.kernel32.GetLogicalDrives()
        for i, l in enumerate(string.ascii_uppercase):
            if mask & (1 << i) and l not in 'AB':
                d = l + ':\\'
                tipo = ctypes.windll.kernel32.GetDriveTypeW(d)   # 2 = removivel, 3 = fixo
                if tipo in (2, 3) and os.path.isdir(d):
                    sitios.append(d)
    else:
        user = os.environ.get('USER') or os.environ.get('LOGNAME') or ''
        for base in ('/run/media/' + user, '/media/' + user, '/media', '/mnt', '/Volumes'):
            try:
                for n in sorted(os.listdir(base)):
                    p = os.path.join(base, n)
                    if os.path.isdir(p) and os.path.ismount(p):
                        sitios.append(p)
            except OSError:
                pass
    out = []
    for p in sitios:
        try:
            nomes = {n.upper() for n in os.listdir(p)}
        except OSError:
            continue
        kairos = 'BIN' in nomes and 'SYS' in nomes
        out.append((p, ('[esxDOS]  ' if kairos else '          ') + p, kairos))
    out.sort(key=lambda x: (not x[2], x[0]))
    return [(p, t) for p, t, _ in out]


def pastas_da_raiz(cartao):
    """[(nome, estado)]: 'sem indices' ou 'tem indices'"""
    out = []
    try:
        nomes = sorted(os.listdir(cartao), key=str.lower)
    except OSError:
        return out
    for n in nomes:
        p = os.path.join(cartao, n)
        if not os.path.isdir(p) or n.upper() in SISTEMA or n.startswith(('.', '$')):
            continue
        tem = os.path.isdir(os.path.join(p, '_NAV')) or os.path.isdir(os.path.join(p, '_nav'))
        out.append((n, 'tem indices' if tem else 'SEM INDICES'))
    return out


class Para_fila:
    # o print do cartao.py vai para a caixa da janela
    def __init__(self, fila): self.fila = fila
    def write(self, t):
        if t: self.fila.put(t)
    def flush(self): pass


class Janela(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title('Kairos - indices do cartao SD')
        self.geometry('760x600')
        self.minsize(560, 420)
        self.fila = queue.Queue()
        self.a_correr = False

        f = ttk.Frame(self, padding=8)
        f.pack(fill='both', expand=True)

        ttk.Label(f, text='1. Clicar no cartao SD:').pack(anchor='w')
        lc = ttk.Frame(f)
        lc.pack(fill='x')
        self.lista_c = tk.Listbox(lc, height=4, exportselection=False)
        self.lista_c.pack(side='left', fill='x', expand=True)
        self.lista_c.bind('<<ListboxSelect>>', lambda e: self.escolheu())
        bc = ttk.Frame(lc)
        bc.pack(side='left', padx=4)
        ttk.Button(bc, text='Actualizar', command=self.enche_cartoes).pack(fill='x')
        ttk.Button(bc, text='Outra pasta...', command=self.outra).pack(fill='x', pady=2)
        self.cartao = None
        self.txt_c = ttk.Label(f, text='(nenhum cartao escolhido)', foreground='gray')
        self.txt_c.pack(anchor='w', pady=(2, 6))

        ttk.Label(f, text='2. Pastas do cartao (escolher para "So\' as escolhidas"; Ctrl/Shift para varias):').pack(anchor='w')
        self.lista_p = tk.Listbox(f, height=8, selectmode='extended', exportselection=False, font='TkFixedFont')
        self.lista_p.pack(fill='both', expand=False)

        self.normal = tk.BooleanVar(value=False)
        ttk.Checkbutton(f, text='Navegador normal (32 colunas): nomes de 17 letras', variable=self.normal).pack(anchor='w', pady=4)

        ttk.Label(f, text='3. O que fazer:').pack(anchor='w')
        bb = ttk.Frame(f)
        bb.pack(fill='x', pady=2)
        self.botoes = []
        for txt, modo in (('So\' o que mudou', 'novas'), ('Refazer tudo', 'tudo'), ('So\' as escolhidas', 'so'),
                          ('Apagar e refazer tudo', 'limpar'), ('Ver (sem escrever)', 'ver')):
            b = ttk.Button(bb, text=txt, command=lambda m=modo: self.corre(m))
            b.pack(side='left', padx=2)
            self.botoes.append(b)

        self.saida = tk.Text(f, height=12, wrap='none', state='disabled')
        self.saida.pack(fill='both', expand=True, pady=(6, 0))

        self.enche_cartoes()
        self.after(100, self.le_fila)

    # --- cartoes
    def enche_cartoes(self):
        self.cs = cartoes()
        self.lista_c.delete(0, 'end')
        for _, t in self.cs:
            self.lista_c.insert('end', t)
        if not self.cs:
            self.lista_c.insert('end', '(nenhum cartao a vista: meter o cartao e carregar em Actualizar)')
        # este programa esta' na raiz de um cartao? escolhe-o logo
        if os.path.isdir(os.path.join(AQUI, 'BIN')) and os.path.isdir(os.path.join(AQUI, 'SYS')):
            self.usa(AQUI)

    def escolheu(self):
        s = self.lista_c.curselection()
        if s and s[0] < len(self.cs):
            self.usa(self.cs[s[0]][0])

    def outra(self):
        d = filedialog.askdirectory(title='A raiz do cartao SD')
        if d:
            self.usa(d)

    def usa(self, d):
        d = os.path.abspath(d)
        self.cartao = d
        tem = os.path.isdir(os.path.join(d, 'BIN')) and os.path.isdir(os.path.join(d, 'SYS'))
        self.txt_c.config(text='Cartao: %s%s' % (d, '' if tem else '   (sem BIN/SYS: e\' mesmo o cartao?)'),
                          foreground='black' if tem else 'red')
        self.lista_p.delete(0, 'end')
        self.pastas = pastas_da_raiz(d)
        for n, e in self.pastas:
            self.lista_p.insert('end', '%-40s %s' % (n, e))

    # --- correr o cartao.py
    def escreve(self, t):
        self.saida.config(state='normal')
        self.saida.insert('end', t)
        self.saida.see('end')
        self.saida.config(state='disabled')

    def corre(self, modo):
        if self.a_correr:
            return
        if not self.cartao:
            messagebox.showinfo('Kairos', 'Primeiro clicar no cartao SD.')
            return
        base = [self.cartao] + (['--normal'] if self.normal.get() else [])
        if modo == 'novas':
            cmds = [base + ['--novas', '--fazer']]
        elif modo == 'tudo':
            cmds = [base + ['--fazer']]
        elif modo == 'so':
            esc = [self.pastas[i][0] for i in self.lista_p.curselection()]
            if not esc:
                messagebox.showinfo('Kairos', 'Escolher primeiro as pastas na lista (Ctrl ou Shift para varias).')
                return
            cmds = [base + ['--fazer', '--so'] + esc]
        elif modo == 'limpar':
            if not messagebox.askyesno('Kairos', 'Apagar todos os indices (_NAV) do cartao e fazer tudo de novo?'):
                return
            cmds = [[self.cartao, '--limpar', '--fazer'], base + ['--fazer']]
        else:
            cmds = [base]
        self.saida.config(state='normal'); self.saida.delete('1.0', 'end'); self.saida.config(state='disabled')
        self.a_correr = True
        for b in self.botoes:
            b.state(['disabled'])
        threading.Thread(target=self.trabalho, args=(cmds,), daemon=True).start()

    def trabalho(self, cmds):
        ok = True
        # o config.ini: ao lado do programa; senao, o da raiz do cartao
        cartao.AQUI = AQUI if os.path.isfile(os.path.join(AQUI, 'config.ini')) else self.cartao
        out = Para_fila(self.fila)
        velho = sys.argv
        for c in cmds:
            try:
                sys.argv = ['cartao.py'] + c
                with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
                    cartao.main()
            except SystemExit as e:
                if e.code not in (None, 0):
                    self.fila.put('%s\n' % e.code); ok = False; break
            except Exception as e:
                self.fila.put('ERRO: %s\n' % e); ok = False; break
            finally:
                sys.argv = velho
        self.fila.put(('fim', ok))

    def le_fila(self):
        try:
            while True:
                m = self.fila.get_nowait()
                if isinstance(m, tuple):
                    self.a_correr = False
                    for b in self.botoes:
                        b.state(['!disabled'])
                    self.escreve('\n== %s ==\n' % ('FEITO' if m[1] else 'PAROU COM ERRO'))
                    if self.cartao:
                        self.usa(self.cartao)
                else:
                    self.escreve(m)
        except queue.Empty:
            pass
        self.after(100, self.le_fila)


if __name__ == '__main__':
    Janela().mainloop()
