# Tapeout BootROM

本文档描述当前 tapebootrom 目录中实际构建并执行的 BootROM 行为；不把尚未接入启动路径的预留代码描述为已支持的启动功能。

## 相关文件

- 入口与当前 BootROM 逻辑：head.S
- 构建规则：Makefile
- 链接脚本：linker/tapeboot.elf.lds
- 内存布局：linker/memory.lds
- GPIO 寄存器偏移：include/devices/gpio.h
- 平台地址定义：include/platform.h
- 预留的 SD 加载器：sd.c

## 内存布局

- BootROM 起始地址：0x00010000
- SoC BootROM 地址映射：0x00010000-0x00011fff（8 KiB）
- 当前 tapebootrom 源镜像链接空间：0x00002000（8 KiB）
- DDR 起始地址：0x80000000

`TapeoutConfig` 通过 `WithBootROM` 将 BootROM 参数配置为 `size = 0x2000`，因此
SoC 侧的 ROM 地址空间是 8 KiB。`linker/memory.lds` 中的 `LENGTH = 0x2000`
同时限制 `tapeboot.bin` 这个源镜像最多能生成 8 KiB；实际镜像不足的部分由 ROM 实现补零。

启用 `USE_SMIC180_ROM=1` 时，使用的 `S018VM_X64Y16D64_PM` 宏为
`1024 x 64 bit = 8192 bytes = 8 KiB`，与 `TapeoutConfig` 的 BootROM 参数一致。

## 当前启动流程

当前生成的 BootROM 是一个最小化跳转桩，流程如下：

1. _prog_start 调用 smp_pause，使非 NONSMP_HART（默认 hart0）的 hart 等待软件中断。
2. 写 GPIO 寄存器：
   - GPIO_INPUT_EN = 0x000
   - GPIO_OUTPUT_EN = 0x1c0
   - GPIO_OUTPUT_VAL = 0x040
3. 调用 resume_pause 发送并处理软件中断，使等待的 hart 继续运行。
4. hart0 将 GPIO_OUTPUT_VAL 更新为 0x180。
5. 每个 hart 将 a0 设为自身的 mhartid，将 a1 设为 dtb 标签地址，然后跳转到 0x80000000。

等价伪代码：

    pause_non_boot_harts();
    gpio_write(INPUT_EN, 0x000);
    gpio_write(OUTPUT_EN, 0x1c0);
    gpio_write(OUTPUT_VAL, 0x040);

    resume_harts();
    if (mhartid == 0)
      gpio_write(OUTPUT_VAL, 0x180);

    a0 = mhartid;
    a1 = &dtb;
    jump(0x80000000);

head.S 当前直接使用 GPIO 基地址 0x10010000，而不是通过 platform.h 中的 GPIO_CTRL_ADDR 间接取得。

## SD 和 FLASH 状态

当前 BootROM **没有实现 SD/FLASH 启动选择**：

- 不读取 GPIO 启动选择位。
- 不调用 sd.c 中的 main()，也不会从 SD 卡加载 payload。
- 不会跳转到 FLASH 地址。
- 当前 Makefile 仅以 head.S 为 BootROM ELF 的输入，sd.c 不在该产物的构建输入中。

sd.c 保留了 SD 卡初始化和 payload 读取逻辑，属于尚未接入的预留代码；它不会改变当前 BootROM 的运行路径。后续若实现 SD 或 FLASH 启动，应同时更新入口汇编、构建规则和本文档。

## 当前限制

- BootROM 不初始化 DDR，直接跳转前提是 0x80000000 已经可访问，且其中已有可执行的下一阶段程序。
- BootROM 不执行 PLL 或时钟初始化。
- .dtb section 目前只有空的 dtb 标签；传入 a1 的不是有效设备树。
- 当前 `tapebootrom` 源镜像和 SoC BootROM 的代码/数据空间都是 8 KiB；如果启动代码超过
  这个大小，需要同步扩大 `linker/memory.lds`、`WithBootROM` 和对应的 SMIC ROM 宏容量。

## 构建

在本目录执行：

    make

构建结果位于 build/：

- tapeboot.elf：带符号 ELF
- tapeboot.bin：去除 0x10000 地址偏移后的 ROM 二进制
- tapeboot.dump：反汇编结果
