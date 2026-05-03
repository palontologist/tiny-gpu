# RV32IM + Custom Extension Instruction Encoders
# Shared helpers for encoding 32-bit RISC-V instructions used by tiny-gpu tests.


def rv32_lui(rd, imm_u):
    """LUI: rd = imm_u << 12"""
    return ((imm_u & 0xFFFFF) << 12) | (rd << 7) | 0b0110111


def rv32_auipc(rd, imm_u):
    """AUIPC: rd = PC + (imm_u << 12)"""
    return ((imm_u & 0xFFFFF) << 12) | (rd << 7) | 0b0010111


def rv32_jal(rd, imm_j):
    """JAL: rd = PC+4, PC = PC + imm_j"""
    imm20 = (imm_j >> 20) & 1
    imm10_1 = (imm_j >> 1) & 0x3FF
    imm11 = (imm_j >> 11) & 1
    imm19_12 = (imm_j >> 12) & 0xFF
    return (
        (imm20 << 31)
        | (imm19_12 << 12)
        | (imm11 << 20)
        | (imm10_1 << 21)
        | (rd << 7)
        | 0b1101111
    )


def rv32_jalr(rd, rs1, imm_i=0):
    """JALR: rd = PC+4, PC = (rs1 + imm_i) & ~1"""
    return ((imm_i & 0xFFF) << 20) | (rs1 << 15) | (0b000 << 12) | (rd << 7) | 0b1100111


def rv32_beq(rs1, rs2, imm_b):
    """BEQ: branch if rs1 == rs2"""
    return _rv32_branch(rs1, rs2, imm_b, 0b000)


def rv32_bne(rs1, rs2, imm_b):
    """BNE: branch if rs1 != rs2"""
    return _rv32_branch(rs1, rs2, imm_b, 0b001)


def rv32_blt(rs1, rs2, imm_b):
    """BLT: branch if rs1 < rs2 (signed)"""
    return _rv32_branch(rs1, rs2, imm_b, 0b100)


def rv32_bge(rs1, rs2, imm_b):
    """BGE: branch if rs1 >= rs2 (signed)"""
    return _rv32_branch(rs1, rs2, imm_b, 0b101)


def rv32_bltu(rs1, rs2, imm_b):
    """BLTU: branch if rs1 < rs2 (unsigned)"""
    return _rv32_branch(rs1, rs2, imm_b, 0b110)


def rv32_bgeu(rs1, rs2, imm_b):
    """BGEU: branch if rs1 >= rs2 (unsigned)"""
    return _rv32_branch(rs1, rs2, imm_b, 0b111)


def _rv32_branch(rs1, rs2, imm_b, funct3):
    """B-type instruction encoder"""
    imm12 = (imm_b >> 12) & 1
    imm10_5 = (imm_b >> 5) & 0x3F
    imm4_1 = (imm_b >> 1) & 0xF
    imm11 = (imm_b >> 11) & 1
    return (
        (imm12 << 31)
        | (imm10_5 << 25)
        | (rs2 << 20)
        | (rs1 << 15)
        | (funct3 << 12)
        | (imm4_1 << 8)
        | (imm11 << 7)
        | 0b1100011
    )


def rv32_lb(rd, rs1, imm_i=0):
    """LB: load byte (signed)"""
    return _rv32_load(rd, rs1, imm_i, 0b000)


def rv32_lh(rd, rs1, imm_i=0):
    """LH: load halfword (signed)"""
    return _rv32_load(rd, rs1, imm_i, 0b001)


def rv32_lw(rd, rs1, imm_i=0):
    """LW: load word (32-bit)"""
    return _rv32_load(rd, rs1, imm_i, 0b010)


def rv32_lbu(rd, rs1, imm_i=0):
    """LBU: load byte (unsigned)"""
    return _rv32_load(rd, rs1, imm_i, 0b100)


def rv32_lhu(rd, rs1, imm_i=0):
    """LHU: load halfword (unsigned)"""
    return _rv32_load(rd, rs1, imm_i, 0b101)


def rv32_vlw_q(vrd, rs1, imm_i=0):
    """VLW.Q: load 128-bit quad-word (custom funct3=011)"""
    return _rv32_load(vrd, rs1, imm_i, 0b011)


def _rv32_load(rd, rs1, imm_i, funct3):
    """I-type load encoder"""
    return (
        ((imm_i & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | 0b0000011
    )


def rv32_sb(rs1, rs2, imm_s=0):
    """SB: store byte"""
    return _rv32_store(rs1, rs2, imm_s, 0b000)


def rv32_sh(rs1, rs2, imm_s=0):
    """SH: store halfword"""
    return _rv32_store(rs1, rs2, imm_s, 0b001)


def rv32_sw(rs1, rs2, imm_s=0):
    """SW: store word (32-bit)"""
    return _rv32_store(rs1, rs2, imm_s, 0b010)


def rv32_vsw_q(rs1, vrs2, imm_s=0):
    """VSW.Q: store 128-bit quad-word (custom funct3=011)"""
    return _rv32_store(rs1, vrs2, imm_s, 0b011)


def _rv32_store(rs1, rs2, imm_s, funct3):
    """S-type store encoder"""
    imm5 = imm_s & 0x1F
    imm7 = (imm_s >> 5) & 0x7F
    return (
        (imm7 << 25)
        | (rs2 << 20)
        | (rs1 << 15)
        | (funct3 << 12)
        | (imm5 << 7)
        | 0b0100011
    )


def rv32_addi(rd, rs1, imm_i):
    """ADDI: rd = rs1 + imm_i"""
    return ((imm_i & 0xFFF) << 20) | (rs1 << 15) | (0b000 << 12) | (rd << 7) | 0b0010011


def rv32_slti(rd, rs1, imm_i):
    """SLTI: rd = (rs1 < imm_i) ? 1 : 0 (signed)"""
    return ((imm_i & 0xFFF) << 20) | (rs1 << 15) | (0b010 << 12) | (rd << 7) | 0b0010011


def rv32_sltiu(rd, rs1, imm_i):
    """SLTIU: rd = (rs1 < imm_i) ? 1 : 0 (unsigned)"""
    return ((imm_i & 0xFFF) << 20) | (rs1 << 15) | (0b011 << 12) | (rd << 7) | 0b0010011


def rv32_xori(rd, rs1, imm_i):
    """XORI: rd = rs1 ^ imm_i"""
    return ((imm_i & 0xFFF) << 20) | (rs1 << 15) | (0b100 << 12) | (rd << 7) | 0b0010011


def rv32_ori(rd, rs1, imm_i):
    """ORI: rd = rs1 | imm_i"""
    return ((imm_i & 0xFFF) << 20) | (rs1 << 15) | (0b110 << 12) | (rd << 7) | 0b0010011


def rv32_andi(rd, rs1, imm_i):
    """ANDI: rd = rs1 & imm_i"""
    return ((imm_i & 0xFFF) << 20) | (rs1 << 15) | (0b111 << 12) | (rd << 7) | 0b0010011


def rv32_slli(rd, rs1, shamt):
    """SLLI: rd = rs1 << shamt"""
    return (
        (0b0000000 << 25)
        | (shamt << 20)
        | (rs1 << 15)
        | (0b001 << 12)
        | (rd << 7)
        | 0b0010011
    )


def rv32_srli(rd, rs1, shamt):
    """SRLI: rd = rs1 >> shamt (logical)"""
    return (
        (0b0000000 << 25)
        | (shamt << 20)
        | (rs1 << 15)
        | (0b101 << 12)
        | (rd << 7)
        | 0b0010011
    )


def rv32_srai(rd, rs1, shamt):
    """SRAI: rd = rs1 >> shamt (arithmetic)"""
    return (
        (0b0100000 << 25)
        | (shamt << 20)
        | (rs1 << 15)
        | (0b101 << 12)
        | (rd << 7)
        | 0b0010011
    )


def rv32_add(rd, rs1, rs2):
    """ADD: rd = rs1 + rs2"""
    return _rv32_rtype(rs1, rs2, 0b000, 0b0000000, rd)


def rv32_sub(rd, rs1, rs2):
    """SUB: rd = rs1 - rs2"""
    return _rv32_rtype(rs1, rs2, 0b000, 0b0100000, rd)


def rv32_sll(rd, rs1, rs2):
    """SLL: rd = rs1 << rs2[4:0]"""
    return _rv32_rtype(rs1, rs2, 0b001, 0b0000000, rd)


def rv32_slt(rd, rs1, rs2):
    """SLT: rd = (rs1 < rs2) ? 1 : 0 (signed)"""
    return _rv32_rtype(rs1, rs2, 0b010, 0b0000000, rd)


def rv32_sltu(rd, rs1, rs2):
    """SLTU: rd = (rs1 < rs2) ? 1 : 0 (unsigned)"""
    return _rv32_rtype(rs1, rs2, 0b011, 0b0000000, rd)


def rv32_xor(rd, rs1, rs2):
    """XOR: rd = rs1 ^ rs2"""
    return _rv32_rtype(rs1, rs2, 0b100, 0b0000000, rd)


def rv32_srl(rd, rs1, rs2):
    """SRL: rd = rs1 >> rs2[4:0] (logical)"""
    return _rv32_rtype(rs1, rs2, 0b101, 0b0000000, rd)


def rv32_sra(rd, rs1, rs2):
    """SRA: rd = rs1 >> rs2[4:0] (arithmetic)"""
    return _rv32_rtype(rs1, rs2, 0b101, 0b0100000, rd)


def rv32_or(rd, rs1, rs2):
    """OR: rd = rs1 | rs2"""
    return _rv32_rtype(rs1, rs2, 0b110, 0b0000000, rd)


def rv32_and(rd, rs1, rs2):
    """AND: rd = rs1 & rs2"""
    return _rv32_rtype(rs1, rs2, 0b111, 0b0000000, rd)


def rv32_mul(rd, rs1, rs2):
    """MUL: rd = rs1 * rs2 (lower 32 bits)"""
    return _rv32_rtype(rs1, rs2, 0b000, 0b0000001, rd)


def rv32_mulh(rd, rs1, rs2):
    """MULH: rd = (rs1 * rs2)[63:32] (signed*signed)"""
    return _rv32_rtype(rs1, rs2, 0b001, 0b0000001, rd)


def rv32_mulhsu(rd, rs1, rs2):
    """MULHSU: rd = (rs1 * rs2)[63:32] (signed*unsigned)"""
    return _rv32_rtype(rs1, rs2, 0b010, 0b0000001, rd)


def rv32_mulhu(rd, rs1, rs2):
    """MULHU: rd = (rs1 * rs2)[63:32] (unsigned*unsigned)"""
    return _rv32_rtype(rs1, rs2, 0b011, 0b0000001, rd)


def rv32_div(rd, rs1, rs2):
    """DIV: rd = rs1 / rs2 (signed)"""
    return _rv32_rtype(rs1, rs2, 0b100, 0b0000001, rd)


def rv32_divu(rd, rs1, rs2):
    """DIVU: rd = rs1 / rs2 (unsigned)"""
    return _rv32_rtype(rs1, rs2, 0b101, 0b0000001, rd)


def rv32_rem(rd, rs1, rs2):
    """REM: rd = rs1 % rs2 (signed)"""
    return _rv32_rtype(rs1, rs2, 0b110, 0b0000001, rd)


def rv32_remu(rd, rs1, rs2):
    """REMU: rd = rs1 % rs2 (unsigned)"""
    return _rv32_rtype(rs1, rs2, 0b111, 0b0000001, rd)


def _rv32_rtype(rs1, rs2, funct3, funct7, rd):
    """R-type instruction encoder"""
    return (
        (funct7 << 25)
        | (rs2 << 20)
        | (rs1 << 15)
        | (funct3 << 12)
        | (rd << 7)
        | 0b0110011
    )


# ---- Custom GPU extensions ----


def rv32_ret():
    """CUSTOM0: thread retirement"""
    return 0b0001011


def rv32_dp4a(rd, rs1, rs2):
    """CUSTOM1 funct3=000: scalar INT4 DP4A (signed)"""
    return _rv32_rtype(rs1, rs2, 0b000, 0b0000000, rd) | (0b0101011 - 0b0110011)


def rv32_dp4au(rd, rs1, rs2):
    """CUSTOM1 funct3=001: scalar INT4 DP4A (unsigned)"""
    return _rv32_rtype(rs1, rs2, 0b001, 0b0000000, rd) | (0b0101011 - 0b0110011)


def rv32_fp_add(rd, rs1, rs2):
    """CUSTOM1 funct3=010: FP32 add stub"""
    return _rv32_rtype(rs1, rs2, 0b010, 0b0000000, rd) | (0b0101011 - 0b0110011)


def rv32_fp_mul(rd, rs1, rs2):
    """CUSTOM1 funct3=011: FP32 mul stub"""
    return _rv32_rtype(rs1, rs2, 0b011, 0b0000000, rd) | (0b0101011 - 0b0110011)


def rv32_custom2(vrd, vrs1, vrs2, funct3, funct7=0):
    """CUSTOM2: 128-bit vector SIMD operation.
    vrd/vrs1/vrs2 are 4-bit vector register indices (v0-v15).
    funct3 selects the vector ALU operation (matches vec_alu.sv VALU_* codes).
    """
    return (
        ((funct7 & 0x7F) << 25)
        | ((vrs2 & 0xF) << 20)
        | ((vrs1 & 0xF) << 15)
        | ((funct3 & 0x7) << 12)
        | ((vrd & 0xF) << 7)
        | 0b1001011
    )


# VALU operation codes (must match vec_alu.sv)
VALU_VADD_I8 = 0b000
VALU_VMUL_I8 = 0b001
VALU_VMADD_I8 = 0b010
VALU_VDP4A_I4 = 0b011
VALU_VADD_F32 = 0b100
VALU_VMUL_F32 = 0b101
VALU_VMADD_F32 = 0b110
VALU_VPREFETCH = 0b111

# ---- Convenience aliases for GPU special registers ----
# In tiny-gpu, x13=%blockIdx, x14=%blockDim, x15=%threadIdx
X_BLOCK_IDX = 13
X_BLOCK_DIM = 14
X_THREAD_IDX = 15
