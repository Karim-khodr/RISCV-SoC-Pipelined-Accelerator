# Human-readable listing for the tracked .hex program.
# The SoC software testbench independently checks every executable word.
# RAM byte addresses: packed A=0x000, packed B=0x004, result=0x030.
# Global MMIO: CONTROL=0x400, STATUS=0x404, VEC_A=0x408,
#              VEC_B=0x40c, RESULT=0x410.
# Register use: x1=packed A, x2=packed B, x3=START,
#               x4=STATUS/masked RESULT_VALID, x5=RESULT.

# PC     word       instruction                 purpose
  0x0000 00002083   lw   x1, 0x000(x0)          load packed VEC_A from RAM
  0x0004 00402103   lw   x2, 0x004(x0)          load packed VEC_B from RAM
  0x0008 40102423   sw   x1, 0x408(x0)          write global MMIO VEC_A
  0x000c 40202623   sw   x2, 0x40c(x0)          write global MMIO VEC_B
  0x0010 00100193   addi x3, x0, 1              construct CONTROL.START
  0x0014 40302023   sw   x3, 0x400(x0)          submit one accelerator command

poll:
  0x0018 40402203   lw   x4, 0x404(x0)          read STATUS
  0x001c 00427213   andi x4, x4, 4              isolate RESULT_VALID (bit 2)
  0x0020 fe020ce3   beq  x4, x0, poll            current PC + (-8) -> 0x0018

  0x0024 41002283   lw   x5, 0x410(x0)          consume RESULT
  0x0028 02502823   sw   x5, 0x030(x0)          store result in normal RAM

halt:
  0x002c 00000000   .word 0x00000000            intentional illegal halt
