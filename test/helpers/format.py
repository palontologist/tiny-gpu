from typing import List, Optional
from .logger import logger


def format_register(register: int) -> str:
    if register == 0:
        return "x0"
    if register < 13:
        return f"x{register}"
    if register == 13:
        return f"x13(%blockIdx)"
    if register == 14:
        return f"x14(%blockDim)"
    if register == 15:
        return f"x15(%threadIdx)"
    return f"x{register}"


def _format_rv32i_instruction(inst_int: int) -> str:
    """Decode a 32-bit RV32I instruction for debug display."""
    opcode = inst_int & 0x7F
    rd = (inst_int >> 7) & 0x1F
    rs1 = (inst_int >> 15) & 0x1F
    rs2 = (inst_int >> 20) & 0x1F
    funct3 = (inst_int >> 12) & 0x7
    funct7 = (inst_int >> 25) & 0x7F

    imm_i = (inst_int >> 20) & 0xFFF
    if imm_i & 0x800:
        imm_i = imm_i - 0x1000

    imm_s = ((inst_int >> 25) & 0x7F) << 5 | ((inst_int >> 7) & 0x1F)
    if imm_s & 0x800:
        imm_s = imm_s - 0x1000

    # B-type immediate
    imm_b = (
        (((inst_int >> 31) & 1) << 12)
        | (((inst_int >> 7) & 1) << 11)
        | (((inst_int >> 25) & 0x3F) << 5)
        | (((inst_int >> 8) & 0xF) << 1)
    )
    if imm_b & 0x1000:
        imm_b = imm_b - 0x2000

    rd_str = format_register(rd)
    rs1_str = format_register(rs1)
    rs2_str = format_register(rs2)

    op_map = {
        0b0110111: "LUI",
        0b0010111: "AUIPC",
        0b1101111: "JAL",
        0b1100111: "JALR",
        0b1100011: "BRANCH",
        0b0000011: "LOAD",
        0b0100011: "STORE",
        0b0010011: "OP-IMM",
        0b0110011: "OP",
        0b0001011: "RET",
        0b0101011: "CUSTOM1",
        0b1001011: "CUSTOM2",
        0b1110011: "SYSTEM",
    }

    op_name = op_map.get(opcode, f"OP_{opcode:07b}")

    if opcode == 0b0110111:
        return f"lui {rd_str}, 0x{imm_i:03X}"
    elif opcode == 0b0010111:
        return f"auipc {rd_str}, 0x{imm_i:03X}"
    elif opcode == 0b1101111:
        return f"jal {rd_str}, {imm_b}"
    elif opcode == 0b1100111:
        return f"jalr {rd_str}, {imm_i}({rs1_str})"
    elif opcode == 0b1100011:
        branch_ops = {
            0b000: "beq",
            0b001: "bne",
            0b100: "blt",
            0b101: "bge",
            0b110: "bltu",
            0b111: "bgeu",
        }
        return f"{branch_ops.get(funct3, 'br')} {rs1_str}, {rs2_str}, {imm_b}"
    elif opcode == 0b0000011:
        load_ops = {
            0b000: "lb",
            0b001: "lh",
            0b010: "lw",
            0b011: "vlw.q",
            0b100: "lbu",
            0b101: "lhu",
        }
        return f"{load_ops.get(funct3, 'load')} {rd_str}, {imm_i}({rs1_str})"
    elif opcode == 0b0100011:
        store_ops = {0b000: "sb", 0b001: "sh", 0b010: "sw", 0b011: "vsw.q"}
        return f"{store_ops.get(funct3, 'store')} {rs2_str}, {imm_s}({rs1_str})"
    elif opcode == 0b0010011:
        imm_ops = {
            0b000: "addi",
            0b010: "slti",
            0b011: "sltiu",
            0b100: "xori",
            0b110: "ori",
            0b111: "andi",
        }
        if funct3 == 0b001:
            return f"slli {rd_str}, {rs1_str}, {rs2}"  # rs2 field holds shamt
        elif funct3 == 0b101:
            return f"{'srai' if funct7 == 0b0100000 else 'srli'} {rd_str}, {rs1_str}, {rs2}"
        return f"{imm_ops.get(funct3, 'op-imm')} {rd_str}, {rs1_str}, {imm_i}"
    elif opcode == 0b0110011:
        if funct7 == 0b0000001:
            mul_ops = {
                0b000: "mul",
                0b001: "mulh",
                0b010: "mulhsu",
                0b011: "mulhu",
                0b100: "div",
                0b101: "divu",
                0b110: "rem",
                0b111: "remu",
            }
            return f"{mul_ops.get(funct3, 'mul')} {rd_str}, {rs1_str}, {rs2_str}"
        else:
            alu_ops = {
                0b000: "add/sub",
                0b001: "sll",
                0b010: "slt",
                0b011: "sltu",
                0b100: "xor",
                0b101: "srl/sra",
                0b110: "or",
                0b111: "and",
            }
            op = alu_ops.get(funct3, "alu")
            if funct3 == 0b000:
                op = "sub" if funct7 == 0b0100000 else "add"
            elif funct3 == 0b101:
                op = "sra" if funct7 == 0b0100000 else "srl"
            return f"{op} {rd_str}, {rs1_str}, {rs2_str}"
    elif opcode == 0b0001011:
        return "ret"
    elif opcode == 0b0101011:
        custom1_ops = {0b000: "dp4a", 0b001: "dp4au", 0b010: "fp.add", 0b011: "fp.mul"}
        return f"{custom1_ops.get(funct3, 'custom1')} {rd_str}, {rs1_str}, {rs2_str}"
    elif opcode == 0b1001011:
        valu_ops = {
            0b000: "vadd.i8",
            0b001: "vmul.i8",
            0b010: "vmadd.i8",
            0b011: "vdp4a.i4",
            0b100: "vadd.f32",
            0b101: "vmul.f32",
            0b110: "vmadd.f32",
            0b111: "vprefetch",
        }
        return f"{valu_ops.get(funct3, 'valu')} v{rd & 0xF}, v{rs1 & 0xF}, v{rs2 & 0xF}"
    elif opcode == 0b1110011:
        return "ecall/ebreak (nop)"

    return f"{op_name} rd={rd_str}, rs1={rs1_str}, rs2={rs2_str}, funct3={funct3}"


def format_instruction(instruction: str) -> str:
    """Format an instruction for debug display.
    Handles both legacy 16-bit custom ISA (for backwards compat) and 32-bit RV32I."""
    if len(instruction) == 16:
        # Legacy 16-bit custom ISA
        opcode = instruction[0:4]
        rd = format_register(int(instruction[4:8], 2))
        rs = format_register(int(instruction[8:12], 2))
        rt = format_register(int(instruction[12:16], 2))
        n = "N" if instruction[4] == 1 else ""
        z = "Z" if instruction[5] == 1 else ""
        p = "P" if instruction[6] == 1 else ""
        imm = f"#{int(instruction[8:16], 2)}"

        if opcode == "0000":
            return "NOP"
        elif opcode == "0001":
            return f"BRnzp {n}{z}{p}, {imm}"
        elif opcode == "0010":
            return f"CMP {rs}, {rt}"
        elif opcode == "0011":
            return f"ADD {rd}, {rs}, {rt}"
        elif opcode == "0100":
            return f"SUB {rd}, {rs}, {rt}"
        elif opcode == "0101":
            return f"MUL {rd}, {rs}, {rt}"
        elif opcode == "0110":
            return f"DIV {rd}, {rs}, {rt}"
        elif opcode == "0111":
            return f"LDR {rd}, {rs}"
        elif opcode == "1000":
            return f"STR {rs}, {rt}"
        elif opcode == "1001":
            return f"CONST {rd}, {imm}"
        elif opcode == "1111":
            return "RET"
        return "UNKNOWN"
    else:
        # 32-bit RV32I
        try:
            inst_int = int(instruction, 2)
            return _format_rv32i_instruction(inst_int)
        except (ValueError, IndexError):
            return f"INVALID({instruction})"


def format_core_state(core_state: str) -> str:
    core_state_map = {
        "000": "IDLE",
        "001": "FETCH",
        "010": "DECODE",
        "011": "REQUEST",
        "100": "WAIT",
        "101": "EXECUTE",
        "110": "UPDATE",
        "111": "DONE",
    }
    return core_state_map[core_state]


def format_fetcher_state(fetcher_state: str) -> str:
    fetcher_state_map = {"000": "IDLE", "001": "FETCHING", "010": "FETCHED"}
    return fetcher_state_map[fetcher_state]


def format_lsu_state(lsu_state: str) -> str:
    lsu_state_map = {"00": "IDLE", "01": "REQUESTING", "10": "WAITING", "11": "DONE"}
    return lsu_state_map[lsu_state]


def format_memory_controller_state(controller_state: str) -> str:
    controller_state_map = {
        "000": "IDLE",
        "010": "READ_WAITING",
        "011": "WRITE_WAITING",
        "100": "READ_RELAYING",
        "101": "WRITE_RELAYING",
    }
    return controller_state_map[controller_state]


def format_registers(registers: List[str]) -> str:
    formatted_registers = []
    for i, reg_value in enumerate(registers):
        decimal_value = int(reg_value, 2)  # Convert binary string to decimal
        # Handle both 16-register legacy and 32-register RV32 formats
        reg_count = len(registers)
        reg_idx = (reg_count - 1) - i  # Register data is provided in reverse order
        formatted_registers.append(f"{format_register(reg_idx)} = {decimal_value}")
    formatted_registers.reverse()
    return ", ".join(formatted_registers)


def format_cycle(dut, cycle_id: int, thread_id: Optional[int] = None):
    logger.debug(
        f"\n================================== Cycle {cycle_id} =================================="
    )

    for core in dut.cores:
        # Not exactly accurate, but good enough for now
        if (
            int(str(dut.thread_count.value), 2)
            <= core.i.value * dut.THREADS_PER_BLOCK.value
        ):
            continue

        logger.debug(
            f"\n+--------------------- Core {core.i.value} ---------------------+"
        )

        instruction = str(core.core_instance.instruction.value)
        for thread in core.core_instance.threads:
            if int(thread.i.value) < int(
                str(core.core_instance.thread_count.value), 2
            ):  # if enabled
                block_idx = core.core_instance.block_id.value
                block_dim = int(core.core_instance.THREADS_PER_BLOCK)
                thread_idx = thread.register_instance.THREAD_ID.value
                idx = block_idx * block_dim + thread_idx

                # Try new rs1/rs2 names, fall back to old rs/rt for legacy
                try:
                    rs1_val = int(str(thread.register_instance.rs1.value), 2)
                    rs2_val = int(str(thread.register_instance.rs2.value), 2)
                    rs_str = f"rs1={rs1_val}, rs2={rs2_val}"
                except AttributeError:
                    try:
                        rs_val = int(str(thread.register_instance.rs.value), 2)
                        rt_val = int(str(thread.register_instance.rt.value), 2)
                        rs_str = f"rs={rs_val}, rt={rt_val}"
                    except AttributeError:
                        rs_str = "N/A"

                reg_input_mux = int(
                    str(core.core_instance.decoded_reg_input_mux.value), 2
                )
                alu_out = int(str(thread.alu_instance.alu_out.value), 2)
                lsu_out = int(str(thread.lsu_instance.lsu_out.value), 2)
                constant = int(str(core.core_instance.decoded_immediate.value), 2)

                if thread_id is None or thread_id == idx:
                    logger.debug(f"\n+-------- Thread {idx} --------+")

                    logger.debug(
                        "PC:", int(str(core.core_instance.current_pc.value), 2)
                    )
                    logger.debug("Instruction:", format_instruction(instruction))
                    logger.debug(
                        "Core State:",
                        format_core_state(str(core.core_instance.core_state.value)),
                    )
                    logger.debug(
                        "Fetcher State:",
                        format_fetcher_state(
                            str(core.core_instance.fetcher_state.value)
                        ),
                    )
                    logger.debug(
                        "LSU State:",
                        format_lsu_state(str(thread.lsu_instance.lsu_state.value)),
                    )

                    # Try 32-register format, fall back to 16-register
                    try:
                        reg_list = [
                            str(item.value) for item in thread.register_instance.regfile
                        ]
                    except AttributeError:
                        try:
                            reg_list = [
                                str(item.value)
                                for item in thread.register_instance.registers
                            ]
                        except AttributeError:
                            reg_list = []

                    if reg_list:
                        logger.debug("Registers:", format_registers(reg_list))
                    logger.debug(rs_str)

                    if reg_input_mux == 0:
                        logger.debug("ALU Out:", alu_out)
                    if reg_input_mux == 1:
                        logger.debug("LSU Out:", lsu_out)
                    if reg_input_mux == 2:
                        logger.debug("Constant:", constant)

        logger.debug("Core Done:", str(core.core_instance.done.value))
