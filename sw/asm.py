#!/usr/bin/env python3
"""
Kurroma-128 : minimalny asembler.
Format instrukcji (32 bity):
  [31:26] opcode(6) | [25:21] rd | [20:16] rs1 | [15:11] rs2 | [10:0] imm11
"""
import sys, re

OPS = {
    'NOP':0x00,'ADD':0x01,'SUB':0x02,'AND':0x03,'OR':0x04,'XOR':0x05,
    'SLL':0x06,'SRL':0x07,'SRA':0x08,'MUL':0x09,'MULH':0x0A,'SLT':0x0B,'SLTU':0x0C,
    'DIV':0x0D,'REM':0x0E,'ADDI':0x0F,'ANDI':0x10,'ORI':0x11,'XORI':0x12,
    'SLLI':0x13,'SRLI':0x14,'SRAI':0x15,'LI':0x16,'LW':0x17,'SW':0x18,
    'LB':0x19,'SB':0x1A,'BEQ':0x1B,'BNE':0x1C,'BLT':0x1D,'BGE':0x1E,
    'JAL':0x1F,'JALR':0x20,'ECALL':0x21,'ERET':0x22,'CSRR':0x23,'CSRW':0x24,
    'FENCE':0x25,'HALT':0x26,
}

def reg(t):
    t = t.strip().lower()
    if not t.startswith('r'):
        raise ValueError('zly rejestr: ' + t)
    n = int(t[1:])
    assert 0 <= n < 32, 'rejestr poza zakresem: ' + t
    return n

def enc(op, rd=0, rs1=0, rs2=0, imm=0):
    imm &= 0x7FF
    return (OPS[op] << 26) | (rd << 21) | (rs1 << 16) | (rs2 << 11) | imm

def assemble(src):
    out = []
    labels = {}
    lines = []
    for raw in src.splitlines():
        line = raw.split('#')[0].split(';')[0].strip()
        if not line:
            continue
        m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$', line)
        if m:
            labels[m.group(1)] = len(lines) * 4
            line = m.group(2).strip()
            if not line:
                continue
        lines.append(line)

    for idx, line in enumerate(lines):
        cur_pc = idx * 4
        parts = re.split(r'[\s,]+', line)
        op = parts[0].upper()
        a = parts[1:]
        if op == 'NOP':
            out.append(enc('NOP'))
        elif op == 'HALT':
            out.append(enc('HALT'))
        elif op == 'ECALL':
            out.append(enc('ECALL'))
        elif op == 'ERET':
            out.append(enc('ERET'))
        elif op == 'FENCE':
            out.append(enc('FENCE'))
        elif op in ('ADD','SUB','AND','OR','XOR','SLL','SRL','SRA','MUL','MULH','SLT','SLTU'):
            out.append(enc(op, reg(a[0]), reg(a[1]), reg(a[2])))
        elif op in ('ADDI','ANDI','ORI','XORI','SLLI','SRLI','SRAI'):
            out.append(enc(op, reg(a[0]), reg(a[1]), 0, int(a[2], 0)))
        elif op == 'LI':
            out.append(enc('LI', reg(a[0]), 0, 0, int(a[1], 0)))
        elif op in ('LW','LB'):
            m = re.match(r'^(-?\w+)\(\s*(r\d+)\s*\)$', a[1])
            imm, base = int(m.group(1), 0), reg(m.group(2))
            out.append(enc(op, reg(a[0]), base, 0, imm))
        elif op in ('SW','SB'):
            m = re.match(r'^(-?\w+)\(\s*(r\d+)\s*\)$', a[1])
            imm, base = int(m.group(1), 0), reg(m.group(2))
            out.append(enc(op, 0, base, reg(a[0]), imm))
        elif op in ('BEQ','BNE','BLT','BGE'):
            tgt = a[2]
            off = (labels[tgt] - cur_pc) if tgt in labels else int(tgt, 0)
            out.append(enc(op, 0, reg(a[0]), reg(a[1]), off))
        elif op == 'JAL':
            tgt = a[1]
            off = (labels[tgt] - cur_pc) if tgt in labels else int(tgt, 0)
            out.append(enc('JAL', reg(a[0]), 0, 0, off))
        elif op == 'JALR':
            out.append(enc('JALR', reg(a[0]), reg(a[1]), 0, int(a[2], 0)))
        elif op == 'CSRR':
            out.append(enc('CSRR', reg(a[0]), 0, 0, int(a[1], 0)))
        elif op == 'CSRW':
            out.append(enc('CSRW', 0, reg(a[0]), 0, int(a[1], 0)))
        else:
            raise ValueError('nieznana instrukcja: ' + op)
    return out

if __name__ == '__main__':
    src = open(sys.argv[1]).read()
    words = assemble(src)
    with open(sys.argv[2], 'w') as f:
        for w in words:
            f.write('%08x\n' % w)
    print('zapisano %d slow (32 b) = %d B do %s' % (len(words), len(words)*4, sys.argv[2]))
