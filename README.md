# EFR32 application template

Bare-metal / FreeRTOS starter for kits and custom boards. Configure the chip and
components in `.slcp`, generate with SLC, build with CMake, write code in `app.c`.

Verified: macOS, SLC 6.0.23, Simplicity SDK 2026.6.1, Arm GCC 14.2.Rel1;
MG24 EUSART (custom board; BRD4186C + BRD4002A bare metal and FreeRTOS),
MG21A020F1024IM32 USART (custom board, bare metal). Other chips must be supported
by the selected SDK and components. Series 1 may require Gecko SDK.

## Dependencies

GNU Make, SLC CLI, Simplicity SDK, Arm GCC, CMake 3.25+, Ninja, Commander and
Python 3.8+ with PyYAML. Put command-line tools on `PATH`. For UART logs install
`tio`; for debugging, J-Link and Arm GDB; for source checks, clang-tidy/clang-format.

The tested Silicon Labs Python includes PyYAML. Select and check it **before Make**:

```sh
export PYTHON="$(slt where python)/bin/python3"
"$PYTHON" -c 'import yaml'
```

Fallback: `python3 -m venv .venv`, `. .venv/bin/activate`,
`python -m pip install PyYAML`, `export PYTHON=python3`.
Generation does not install tools/packages or configure your shell.

## Create a project

1. Copy the template, including hidden files and `tools/`.
2. Rename `tbd.slcp`; set `project_name`, `label`, `sdk.version` and the exact part
   under **Target**. Keep one `.slcp` and one explicit EFR32 part. Names use
   letters, digits, `_`, `-`, `.`.
3. Follow **Kit** or **Custom board** below. The default is MG24 with no kit wiring.

Make finds the SDK through SLT. Override with `SDK=/absolute/path/to/sdk` when needed.
Add application sources to `.slcp` under `source`.

## Apply to an existing project

A project started from a Simplicity Studio example keeps its own sources, `.slcp`
and readme; `apply.sh` adds the reusable part of this template: `Makefile`,
`tools/`, clang and Zed configuration, `.gitignore` and the CI workflow. Run it
from anywhere, for example inside the project:

```sh
~/path/to/efr32-project-template/apply.sh .
```

Rerun it after the template changes. Existing files that differ are reported
and kept: add `--diff` to see the changes, `--force` to overwrite them, or `--dry-run`
to report without writing. `--remove` deletes the same files again, with the
same rules for files that differ; build output stays, so run `make clean` first
if you want it gone.

Studio example sources are not formatted to `.clang-format`; run `clang-format -i`
on them once so `make check-format` passes. Studio also generates `cmake_iar/`
and `cmake_llvm/`; `.gitignore` leaves them out because the Makefile builds with
GCC only.

## Kit: BRD4186C on BRD4002A motherboard

1. In `.slcp` **Kit example**, uncomment both complete board entries.
2. In **Kit only**, uncomment `SL_BOARD_ENABLE_VCOM` and its value.
3. Comment out the complete **Custom-board UART** entry, including `instance`.
   Keep `app_log` enabled.
4. Run `make regenerate`, connect the motherboard's debugger/VCOM USB connection
   to your computer, then follow **Read logs** below.

Board components supply the UART driver, pins and flow-control configuration;
leave those settings as supplied. For another kit, use its matching part and
board components. If its board has no VCOM recommendation, select one UART
driver matching its schematic and SDK config. Keep only one stream named `vcom`.

## Custom board: UART

1. Leave the kit entries commented. In **Custom-board UART**, use
   `iostream_eusart` for MG24 or `iostream_usart` for MG21, with instance `vcom`.
   For other supported chips, prefer EUSART when available, otherwise USART.
   Select one driver: MG24 has both peripherals, so capability alone is ambiguous.
2. Run `make generate` to create the config headers without building.
3. Assign peripheral/pins according to your schematic using Pin Tool or the
   driver's annotated config header. Preserve the Pin Tool annotations.

MG24 example: in `config/sl_iostream_eusart_vcom_config.h`, replace the warning
and commented placeholders inside the pin region with:

```c
#define SL_IOSTREAM_EUSART_VCOM_PERIPHERAL      EUSART0
#define SL_IOSTREAM_EUSART_VCOM_PERIPHERAL_NO   0
#define SL_IOSTREAM_EUSART_VCOM_TX_PORT         SL_GPIO_PORT_A
#define SL_IOSTREAM_EUSART_VCOM_TX_PIN          8
#define SL_IOSTREAM_EUSART_VCOM_RX_PORT         SL_GPIO_PORT_A
#define SL_IOSTREAM_EUSART_VCOM_RX_PIN          9
```

For this example, keep `SL_IOSTREAM_EUSART_VCOM_FLOW_CONTROL_TYPE` set to
`SL_IOSTREAM_EUSART_UART_FLOW_CTRL_NONE`. Review clocks/power and other drivers
for your board, then run `make regenerate`.

The tested MG21 example uses `sl_iostream_usart_vcom_config.h`,
`SL_IOSTREAM_USART_VCOM_*` macros, USART0, `SL_GPIO_PORT_A`, TX=0, RX=1 and
`usartHwFlowControlNone`. Use `SL_GPIO_PORT_*`: the SDK's commented `gpioPortA`
placeholders caused Pin Tool location mismatches in this SDK version.

Connect a USB–UART adapter compatible with the board's I/O voltage:
target TX → adapter RX, target RX → adapter TX, common GND. Follow **Read logs**.

## Read logs (both board types)

`app_log` writes to the UART stream named `vcom`. On a kit, the motherboard bridges
it to USB; a custom board needs its own bridge/adapter. The stream name does not
create a USB interface. Logger routing is already configured; no manual UART
initialization is needed. Add messages with `app_log_info("message" APP_LOG_NL)`.

```sh
make flash
make monitor-vcom PORT=/dev/...     # choose the kit/adapter serial port
```

With the monitor open, reset the board using its button or `make reset` in another
terminal. The existing `app_init()` prints `app started` once. `make flashm`
combines flash and monitor, but may miss this message before the monitor opens.
Exit `tio` with Ctrl-T Q.

The monitor reads baud rate from the driver header (initially 921600). To change
it after generation, edit that header, rebuild and reflash. Logger settings live
in `config/app_log_config.h`; UART and instance `"vcom"` are the existing defaults.

## Configuration and Git

- `.slcp`: chip, components and initial values. Ordinary regeneration preserves
  existing config headers; changing `.slcp` baud alone need not update the header.
- `config/`: driver settings and annotated pins. Edit the actual driver header or
  use Pin Tool. Editing `pin_config.h` alone need not configure that driver.
- `.pintool`: Pin Tool state. Commit it **together with `config/`**, application
  sources, `.slcp` and generated build inputs used by your project.

Changing board components does not guarantee replacement of preserved configs.
For another board, start fresh and migrate application code/configuration.
Keep `cmake_gcc/autogen_toolchain.cmake` out of Git: it contains machine defaults.

## Bare metal / FreeRTOS

Bare metal calls `app_process_action()` repeatedly. For FreeRTOS, uncomment the
complete **Optional kernel** entry and run `make regenerate`. Create working
tasks in `app_init()`; `app_process_action()` does not become a continuous RTOS
loop. The existing `main.c` supports both modes; keep its integration unchanged.

## Commands

| Command | Action |
| --- | --- |
| `make generate` / `make build` / `make regenerate` | Generate / build / both |
| `make clean` | Delete build output and compilation database |
| `make flash` / `make flashm` | Build and flash / then open logs |
| `make monitor-vcom PORT=/dev/...` | UART logs |
| `make monitor-rtt` / `make monitor-auto` | RTT / transport selected in app_log config |
| `make reset` / `make erase` | Reset / mass erase connected target |
| `make debug-server` / `make debug` | J-Link server / build, connect, reset and load |
| `make zed-debug-config` | Generate local Zed debug configuration |
| `make lint` / `make check-format` / `make check` | Analysis / formatting / both |

RTT requires a configured RTT stream; exit Commander with Ctrl-C. Run the debug
server in a separate terminal. Override `JLINK_DEVICE` if J-Link needs another
part alias. Tool executable overrides: `PYTHON`, `SLC`, `CMAKE`, `GDB`,
`JLINK_GDB_SERVER`.

## Build on another machine

Set up dependencies/Python above. Default `SLC_COPY=-cpsdk` copies required SDK
sources; `SLC_COPY=-nocp` keeps references to the installed SDK.
Without `autogen_toolchain.cmake`, supply these paths and discard the old cache:

```sh
export ARM_GCC_DIR=/absolute/path/to/arm-gnu-toolchain
export POST_BUILD_EXE=/absolute/path/to/commander
export NINJA_EXE_PATH=/absolute/path/to/ninja
make clean
make build
```

`ARM_GCC_DIR` contains `bin/`; the other paths are executables. On macOS Commander
is typically `Commander.app/Contents/MacOS/commander`. Ninja can also be on `PATH`.
A `-nocp` project still needs its referenced SDK paths. Only GCC is supported.

## Editor, CI and limits

Build prepares the CMake compilation database for clangd/clang-tidy by adding
GCC's sysroot; this avoids `stdlib.h` errors and does not change firmware builds.
Zed tasks need the same `PYTHON`/`PATH` as terminal Make. Rerun `zed-debug-config`
after moving/renaming the project. CI checks formatting and validates the
clang-tidy configuration; it does not analyze or build firmware. Full `make check`
is currently local and needs a generated project with assigned pins.
Source checks cover `.c`/`.h`, not C++ files. The CI job is skipped in
`sivakov512/efr32-project-template`; it runs automatically in a new repository
created from this template. The skipped workflow may still appear in Actions.

CLI generation/builds were tested. GUI workflows, hardware UART/flashing/debugging,
GitHub CI execution, other SDK versions, Series 1/3, Windows/Linux and paths with
spaces were not verified. One generation is sufficient; custom pins must still
be assigned. `Unknown peripheral None` appeared in both working kit and
unconfigured custom projects: inspect configs and build results.

References: [SLC generation](https://docs.silabs.com/simplicity-slc/6.0.22/slc-common-workflows/generate-a-new-project),
[component conditions](https://siliconlabs.github.io/slc-specification/1.2/format/project/component/).
