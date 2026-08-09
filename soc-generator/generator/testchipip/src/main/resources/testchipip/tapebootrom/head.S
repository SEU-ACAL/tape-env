// See LICENSE.Sifive for license details.
#include <platform.h>
#include <smp.h>
#include "common.h"

// 理论上这段在platform.h中
#define GPIO_BASE_ADDR 0x10010000 // GPIO基地址
#define DDR_BASE_ADDR 0x80000000 // DDR基地址


  .section .text.init
  .option norvc
  .globl _prog_start

/*
smp_pause 作用：让除了主核（一般是hart0）以外的所有核暂停（等待中断），只让主核继续执行。
执行步骤
1. 设置 mie（Machine Interrupt Enable）寄存器，只允许软件中断（0x8）。
2. 判断当前核是不是主核（NONSMP_HART，默认0）。
3. 如果不是主核，直接跳到42标签，执行wfi（Wait For Interrupt），进入低功耗等待状态，直到被唤醒。
4. 只有主核会继续往下执行。
*/

/* GPIO
  ie oe = 1 输出
  ie oe = 0 输入
*/

/**
  0-5 输入
  6-11 输出
**/


_prog_start:
  smp_pause(s1, s2)

// 大核心 , 晶振跑
// gpio 初始化，使能输入输出引脚


gpio_init:
    //GPIO init , 0-5 ie,oe = 1 , 6-11 ie,oe = 0
    li t0,GPIO_BASE_ADDR
    addi t1,t0, GPIO_OUTPUT_EN
    addi t2,t0, GPIO_INPUT_EN
    li t3 ,0x00
    sw t3, 0(t2) //
    li t3, 0x1C0
    sw t3, 0(t1) //
    // 所有gpio 输出0
    addi t4,t0, GPIO_OUTPUT_VAL
    li t5, 0x40  // 点亮gpio6
    sw t5, 0(t4)


boot_ddr:
  resume_pause(s1, s2)
  li   s1, NONSMP_HART
  csrr s2, mhartid
  bne  s1, s2, jump_led

  li t2,GPIO_BASE_ADDR
  addi t2,t2, GPIO_OUTPUT_VAL
  li t3, 0x180
  sw t3, 0(t2) // 点亮gpio7,8


jump_led:
  li   s3, DDR_BASE_ADDR
  csrr a0, mhartid // hartid for next level bootloader
  la a1, dtb // dtb address for next level bootloader
  jr   s3


  .section .dtb
  .align 3
dtb:
