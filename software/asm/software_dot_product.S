# Synchronized human-readable listing.
#
# This file is a manually synchronized human-readable listing and is not
# assembled or parsed by the build. The SoC software testbench independently constructs
# the expected executable words with instruction encoders, loads the tracked
# .hex image, compares it word-for-word with those generated words, and checks
# fixed machine-code audit values before execution.
# RAM byte addresses: A0..A3=0x010,0x014,0x018,0x01c;
#                     B0..B3=0x020,0x024,0x028,0x02c;
#                     software result=0x034.
# Register use: x1=constant one, x2=dot-product sum, x3=multiplicand,
#               x4=decrementing multiplier, x5..x8=lane products.
# Multiplication is repeated addition; no MUL or unsupported instruction is used.

# PC     word       instruction                 purpose
  0x0000 00100093   addi x1, x0, 1              constant decrement value
  0x0004 00000113   addi x2, x0, 0              clear final sum

  0x0008 01002183   lw   x3, 0x010(x0)          load A0 = 2
  0x000c 02002203   lw   x4, 0x020(x0)          load B0 = 1
  0x0010 00000293   addi x5, x0, 0              clear product 0
mul0:
  0x0014 00020863   beq  x4, x0, done0          current PC + 16 -> 0x0024
  0x0018 003282b3   add  x5, x5, x3             product 0 += A0
  0x001c 40120233   sub  x4, x4, x1             B0 counter -= 1
  0x0020 fe000ae3   beq  x0, x0, mul0            current PC + (-12) -> 0x0014
done0:
  0x0024 00510133   add  x2, x2, x5             sum += product 0

  0x0028 01402183   lw   x3, 0x014(x0)          load A1 = 4
  0x002c 02402203   lw   x4, 0x024(x0)          load B1 = 3
  0x0030 00000313   addi x6, x0, 0              clear product 1
mul1:
  0x0034 00020863   beq  x4, x0, done1          current PC + 16 -> 0x0044
  0x0038 00330333   add  x6, x6, x3             product 1 += A1
  0x003c 40120233   sub  x4, x4, x1             B1 counter -= 1
  0x0040 fe000ae3   beq  x0, x0, mul1            current PC + (-12) -> 0x0034
done1:
  0x0044 00610133   add  x2, x2, x6             sum += product 1

  0x0048 01802183   lw   x3, 0x018(x0)          load A2 = 6
  0x004c 02802203   lw   x4, 0x028(x0)          load B2 = 5
  0x0050 00000393   addi x7, x0, 0              clear product 2
mul2:
  0x0054 00020863   beq  x4, x0, done2          current PC + 16 -> 0x0064
  0x0058 003383b3   add  x7, x7, x3             product 2 += A2
  0x005c 40120233   sub  x4, x4, x1             B2 counter -= 1
  0x0060 fe000ae3   beq  x0, x0, mul2            current PC + (-12) -> 0x0054
done2:
  0x0064 00710133   add  x2, x2, x7             sum += product 2

  0x0068 01c02183   lw   x3, 0x01c(x0)          load A3 = 8
  0x006c 02c02203   lw   x4, 0x02c(x0)          load B3 = 7
  0x0070 00000413   addi x8, x0, 0              clear product 3
mul3:
  0x0074 00020863   beq  x4, x0, done3          current PC + 16 -> 0x0084
  0x0078 00340433   add  x8, x8, x3             product 3 += A3
  0x007c 40120233   sub  x4, x4, x1             B3 counter -= 1
  0x0080 fe000ae3   beq  x0, x0, mul3            current PC + (-12) -> 0x0074
done3:
  0x0084 00810133   add  x2, x2, x8             sum += product 3
  0x0088 02202a23   sw   x2, 0x034(x0)          store software result in RAM

halt:
  0x008c 00000000   .word 0x00000000            intentional illegal halt
