# BootROM 分析

## 相关文件

- 入口文件：`tapeout/boot/head.S`
- SD 加载器：`tapeout/boot/sd.c`
- 链接脚本：`tapeout/boot/linker/sdboot.elf.lds`
- 内存映射：`tapeout/boot/linker/memory.lds`
- GPIO 寄存器偏移：`tapeout/boot/include/devices/gpio.h`
- 平台地址定义：`tapeout/boot/include/platform.h`

## 总览

这个 BootROM 本质上是一个比较薄的一级启动器，不负责完整的平台初始化。它当前主要做四件事：

1. 暂停非 0 号 hart，只让 `hart0` 先执行。
2. 初始化 GPIO，并读取启动模式相关输入位。
3. 按条件从 SD 卡把原始 payload 搬运到 DDR。
4. 最后直接跳到 DDR 或 FLASH 基地址执行。

BootROM 自身链接在 `0x10000`，`bootrom_mem` 大小为 `0x2000`。主存起始地址为 `0x80000000`。

## 关键地址

- BootROM 基地址：`0x00010000`
- BootROM 大小：`0x00002000`
- DDR 基地址：`0x80000000`
- FLASH 基地址：`0x20000000`
- `head.S` 中使用的 GPIO 基地址：`0x10010000`

注意：`head.S` 里直接硬编码了 GPIO 基地址，没有使用 `platform.h` 里的 `GPIO_CTRL_ADDR`。这说明这段启动流程是面向当前板级环境定制过的。

## 启动流程

可以先把主流程概括成下面这样：

```c
_start:
  pause_other_harts();
  gpio_init();

  if (custom_boot_bit == 0) {
    sp = 0x8ffff000;
    sd_main();              // 从 SD 加载 payload 到 0x80000000
  }

  wake_other_harts();
  target = boot_sel_bit ? 0x80000000 : 0x20000000;
  a0 = mhartid;
  a1 = &dtb;
  jump(target);
```

更细一点的执行过程如下：

1. `_prog_start` 调用 `smp_pause`，因此一开始只有 `hart0` 继续执行。
2. `gpio_init` 配置 GPIO 输出方向，并点亮一个状态灯。
3. `custom_boot` 读取 GPIO 的 `bit5`。
   - `bit5 = 1`：跳过 SD 加载，直接进入最终启动源选择。
   - `bit5 = 0`：进入 `sd_load`。
4. `sd_load` 把 `sp` 设到 DDR 中，然后调用 `sd.c` 里的 `main()`。
5. `main()` 会初始化 UART 和 SPI，向 SD 卡发送初始化命令，然后把固定位置的原始 payload 复制到 `0x80000000`。
6. SD 加载返回后，或者本来就跳过了 SD，加代码继续读取 GPIO 的 `bit4`。
   - `bit4 = 1`：跳转到 DDR 基地址 `0x80000000`
   - `bit4 = 0`：跳转到 FLASH 基地址 `0x20000000`
7. 最终跳转前，会设置 `a0 = mhartid`、`a1 = dtb`，然后跳到选中的目标地址。

## 启动模式引脚

当前有效代码里真正参与启动判断的是两个输入位：

- `bit5`：`CUSTOM_BOOT`
- `bit4`：`BOOT_SEL`

实际行为如下：

- `bit5 = 1`，`bit4 = 0`：跳过 SD，直接跳到 FLASH
- `bit5 = 1`，`bit4 = 1`：跳过 SD，直接跳到 DDR
- `bit5 = 0`，`bit4 = 1`：先从 SD 加载到 DDR，再跳到 DDR
- `bit5 = 0`，`bit4 = 0`：会尝试做 SD 加载，但最终仍然跳到 FLASH

这里有个关键点：SD 不是一个独立的最终启动目标。它更像是“先搬数据”的一步，最后真正跳到哪里，仍然由 `bit4` 决定。

## GPIO 在各个阶段的行为

当前生效的代码里，GPIO 只承担两类功能：

1. 读取启动模式输入位。
2. 输出不同的 LED 状态，表示当前所处阶段。

### GPIO 寄存器用法

- `GPIO_INPUT_VAL  = 0x00`
- `GPIO_INPUT_EN   = 0x04`
- `GPIO_OUTPUT_EN  = 0x08`
- `GPIO_OUTPUT_VAL = 0x0c`

### 初始化阶段

在 `gpio_init` 中，代码会执行：

- `INPUT_EN = 0x000`
- `OUTPUT_EN = 0x1c0`
- `OUTPUT_VAL = 0x040`

对应效果：

- 使能输出位：`bit6`、`bit7`、`bit8`
- 初始灯态：只点亮 `gpio6`

### 分阶段 GPIO 状态表

| 阶段 | GPIO 输入 | GPIO 动作 | 含义 |
| --- | --- | --- | --- |
| 进入 BootROM | 暂未采样输入 | `OUTPUT_VAL = 0x040` | 点亮 `gpio6`，表示已进入 BootROM |
| 判断是否进入 SD | 读取 `bit5` | 无额外输出变化 | `bit5 = 0` 进入 SD 加载；`bit5 = 1` 跳过 SD |
| 进入 SD 加载 | `bit5 = 0` | `OUTPUT_VAL = 0x080` | 点亮 `gpio7`，表示正在执行 SD 加载 |
| SD 结束或跳过 SD | `bit5 = 0` 表示 SD 返回；`bit5 = 1` 表示本来就跳过 SD | `OUTPUT_VAL = 0x100` | 点亮 `gpio8`，表示即将进入最终启动源选择 |
| 判断 DDR / FLASH | 读取 `bit4` | 无额外输出变化 | `bit4 = 0` 走 FLASH；`bit4 = 1` 走 DDR |
| 准备跳 FLASH | `bit4 = 0` | `OUTPUT_VAL = 0x0c0` | 点亮 `gpio6 + gpio7` |
| 准备跳 DDR | `bit4 = 1` | `OUTPUT_VAL = 0x180` | 点亮 `gpio7 + gpio8` |
| 最终跳转前 | 最终目标由 `bit4` 决定；`bit5` 只影响是否做过 SD 加载 | `OUTPUT_VAL = 0x1c0` | 点亮 `gpio6 + gpio7 + gpio8`，随后跳转到 FLASH 或 DDR |

### 输入位采样位置

- `bit5` 在 `custom_boot` 阶段被读取。
- `bit4` 在 `skip_sd_load` 阶段被读取。

### 输入组合和最终路径对应关系

| `bit5` (`CUSTOM_BOOT`) | `bit4` (`BOOT_SEL`) | 是否执行 SD 加载 | 最终跳转目标 |
| --- | --- | --- | --- |
| `1` | `0` | 否 | FLASH (`0x20000000`) |
| `1` | `1` | 否 | DDR (`0x80000000`) |
| `0` | `0` | 是 | FLASH (`0x20000000`) |
| `0` | `1` | 是 | DDR (`0x80000000`) |

### 不同输入下最后的灯状态

下面这张表按 `hart0` 的执行路径来看“最后灯态”。

需要区分两件事：

- `boot_flash` / `boot_ddr` 分支里会先写一次分支灯态。
- 进入 `boot_jump` 后，`hart0` 还会再写一次 `OUTPUT_VAL = 0x1c0`。

因此，如果严格按“最后一次写 GPIO_OUTPUT_VAL”来定义，那么四种输入组合最终看到的灯态其实都是一样的，都会变成 `0x1c0`。

| `bit5` (`CUSTOM_BOOT`) | `bit4` (`BOOT_SEL`) | 是否执行 SD 加载 | 最终跳转目标 | 分支阶段灯态 | 最后一次写 GPIO 后的灯态 |
| --- | --- | --- | --- | --- | --- |
| `1` | `0` | 否 | FLASH (`0x20000000`) | `0x0c0`，点亮 `gpio6 + gpio7` | `0x1c0`，点亮 `gpio6 + gpio7 + gpio8` |
| `1` | `1` | 否 | DDR (`0x80000000`) | `0x180`，点亮 `gpio7 + gpio8` | `0x1c0`，点亮 `gpio6 + gpio7 + gpio8` |
| `0` | `0` | 是 | FLASH (`0x20000000`) | `0x0c0`，点亮 `gpio6 + gpio7` | `0x1c0`，点亮 `gpio6 + gpio7 + gpio8` |
| `0` | `1` | 是 | DDR (`0x80000000`) | `0x180`，点亮 `gpio7 + gpio8` | `0x1c0`，点亮 `gpio6 + gpio7 + gpio8` |

也就是说：

- 想区分最终跳的是 FLASH 还是 DDR，看分支阶段灯态更有意义。
- 如果只看“最后稳定在什么值”，那四种输入最后都会到 `0x1c0`。

### 不同输入下的灯状态变化时序

下面这张表按正常启动路径列出 LED 的变化过程。每个箭头表示一次新的 `OUTPUT_VAL` 写入。

| `bit5` (`CUSTOM_BOOT`) | `bit4` (`BOOT_SEL`) | 启动路径 | 灯状态变化 |
| --- | --- | --- | --- |
| `1` | `0` | 跳过 SD，最终跳 FLASH | `0x040`（进入 BootROM，亮 `gpio6`） -> `0x100`（进入最终启动源选择，亮 `gpio8`） -> `0x0c0`（FLASH 分支，亮 `gpio6 + gpio7`） -> `0x1c0`（最终跳转前，亮 `gpio6 + gpio7 + gpio8`） |
| `1` | `1` | 跳过 SD，最终跳 DDR | `0x040`（进入 BootROM，亮 `gpio6`） -> `0x100`（进入最终启动源选择，亮 `gpio8`） -> `0x180`（DDR 分支，亮 `gpio7 + gpio8`） -> `0x1c0`（最终跳转前，亮 `gpio6 + gpio7 + gpio8`） |
| `0` | `0` | 先做 SD 加载，最终跳 FLASH | `0x040`（进入 BootROM，亮 `gpio6`） -> `0x080`（进入 SD 加载，亮 `gpio7`） -> `0x100`（SD 返回后进入最终启动源选择，亮 `gpio8`） -> `0x0c0`（FLASH 分支，亮 `gpio6 + gpio7`） -> `0x1c0`（最终跳转前，亮 `gpio6 + gpio7 + gpio8`） |
| `0` | `1` | 先做 SD 加载，最终跳 DDR | `0x040`（进入 BootROM，亮 `gpio6`） -> `0x080`（进入 SD 加载，亮 `gpio7`） -> `0x100`（SD 返回后进入最终启动源选择，亮 `gpio8`） -> `0x180`（DDR 分支，亮 `gpio7 + gpio8`） -> `0x1c0`（最终跳转前，亮 `gpio6 + gpio7 + gpio8`） |

从这张表可以直接看出：

- `bit5` 只决定中间会不会出现 `0x080` 这个“SD 加载中”灯态。
- `bit4` 决定分支灯态是 `0x0c0`（FLASH）还是 `0x180`（DDR）。
- 四种输入组合最后都会进入 `0x1c0`。

### 一个实现细节

这里每次写的都是整个 `OUTPUT_VAL` 寄存器，不是按位累加置位。所以 LED 显示是“覆盖切换”，不是“在原状态上继续点亮更多位”。

## SD 加载路径

`sd.c` 中的 SD 加载器大致做下面这些事：

1. 初始化 UART，用于打印调试信息。
2. 初始化 SPI，用于访问 SD 卡。
3. 发送 `CMD0`、`CMD8`、`ACMD41`、`CMD16`。
4. 从固定起始扇区 `34` 开始读取。
5. 把 `30 MiB` 的原始 payload 复制到 `PAYLOAD_DEST`，默认就是 `0x80000000`。
6. 返回前执行一次 `fence.i`。

这里加载的是原始二进制镜像，不是文件系统中的文件。

## SMP 行为

BootROM 使用了 `include/smp.h` 中的 `smp_pause` / `resume_pause` 宏。

- 非 0 号 hart 一开始会停在 `wfi`。
- 后续 `resume_pause` 通过 CLINT 发送软件中断，把其他 hart 唤醒。
- 其他 hart 会在最终选择启动源并准备跳转前被放开。

## 当前实现的限制和风险

### 1. 默认假设 DDR 已经可用

`sd_load` 把栈放在 DDR 的 `0x8ffff000`，payload 目标地址也是 DDR 的 `0x80000000`。但当前 BootROM 并没有做 DDR 初始化，所以 SD 启动路径实际上依赖一个前提：在进入 `sd_load` 之前，DDR 就必须已经能正常访问。

### 2. SD 失败不会阻止后续启动流程

`sd.c` 里的 `main()` 即使返回错误，`head.S` 也不会检查返回值。`call main` 之后，代码仍会继续进入正常的 DDR/FLASH 选择分支。

### 3. `dtb` 目前是空的

最终跳转前会把 `a1` 设成 `dtb`，但当前 `.dtb` section 里只有一个空标签，并没有真正的设备树内容。因此这里传下去的只是一个占位地址，不是有效 FDT。

### 4. PLL 和时钟切换逻辑当前未启用

`head.S` 中有一大段 PLL / 时钟选择相关代码，但它整体被注释掉了。也就是说，当前生效路径并不负责 PLL bring-up，而是依赖默认时钟环境。

### 5. 注释和实际实现并不完全一致

有几处值得注意的不一致：

- 某些注释把 `bit4` / `bit5` 解释成 `GPIO7` / `GPIO8`，但代码真正读取的是输入值的第 4 位和第 5 位。
- 注释里写了 `0-5` 是输入，但代码把 `INPUT_EN` 写成了 `0x000`。如果这里用的是标准 SiFive 语义，这可能是个潜在 bug；如果是自定义 GPIO 实现，也可能依然能读到输入值。

## 总结

这版 BootROM 更适合被理解为：

- 一个面向当前板级环境定制的启动桩代码；
- 通过 GPIO 决定启动路径；
- 可选地先把 SD 中的 payload 搬到 DDR；
- 最后直接跳到 DDR 或 FLASH 执行。

它还不是一个完整的 bring-up ROM，因为当前有效路径里没有做 DDR 初始化、真实 DTB 传递以及 PLL 初始化。
