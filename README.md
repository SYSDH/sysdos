<h1 align="center">SysDOS</h1>

<p align="center">
  <img src="https://img.shields.io/badge/language-HASM-orange?cacheSeconds=300" alt="HASM">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/SYSDH/sysdos?cacheSeconds=300" alt="License"></a>
  <img src="https://img.shields.io/github/stars/SYSDH/sysdos?cacheSeconds=300" alt="GitHub stars">
</p>

<br>

## 🖥️ Description

**SysDOS** is the "silicon brain" of the SYSDH ecosystem. It is a lightweight, 32-bit monolithic operating system written entirely in **HASM** (SYSDH Assembly). It runs on top of the **SysVM** and provides the necessary infrastructure to stop managing raw bytes like a "peasant" and start running actual programs.

It features a custom Kernel with dynamic memory allocation, a stable **Syscall API** via jump table, a program loader with magic number verification, and a functional Shell (**SYSSH**) to interact with the virtual machine.

<br>

## 🛠️ Features

*   **Monolithic Kernel:** Centralized management for I/O, memory, and system panics.
*   **Syscall Jump Table:** Stable entry points for system functions starting at `0x10000` (65.536).
*   **Dynamic Memory (Kalloc/Kfree):** A built-in heap manager with boundary safety.
*   **Dynamic Program Loader:** Capable of loading and executing external `.bin` files from disk into memory.
*   **SYSSH Shell:** A CLI that supports internal commands (`cls`, `restart`, `shutdown`) and external binary execution.
*   **HioLib:** High-level I/O library for string manipulation and formatted output.
*   **Safety Magic:** Integrated check for the `3301` magic number to ensure the loader doesn't try to "eat garbage".

<br>

## 🧠 Memory Map (The Plan)

The SysDOS manages 1MB of RAM with the following layout:

| Address Range             | Usage                                       |
| :------------------------ | :------------------------------------------ |
| `0x00000 - 0x0FFFF`       | **Kernel & OS Binary** (Code Area)          |
| `0x10000 - 0x107FF`       | **Syscall Jump Table** (2KB Area)           |
| `0x10800 - 0x11167`       | **Kernel Registry Backups** (Libs/Utils)    |
| `0x11168 - 0x11170`       | **Kernel Specials** (Fixed Addresses)       |
| `0x11171 - 0xC3500`       | **OS Dynamic Area** (Heap / Kalloc Zone)    |
| `0xC3501 - 0xF4234`       | **Disk Buffer Area** (Loader Destination)   |
| `0xF4235 - 0xF4258`       | **Loader Register Save Area**               |
| `0xF4259 - 0x100000`      | **System Stack** (Hardware Pb)              |

<br>

## 🐚 SYSSH Commands

*   `cls`: Clears the screen using ANSI escape sequences.
*   `restart`: Re-initializes the kernel and jumps back to the start.
*   `shutdown`: Safely terminates the SysVM.
*   `exit`: Exits the shell environment.
*   **External Programs:** Type any name to search for and execute a binary located in `./sysdos/bin/`.

<br>

## 🚀 How to build and run

### Requirements
*   [SysVM](https://github.com/sysdh/sysvm) (The hardware)
*   [SysASM](https://github.com/sysdh/sysasm) (The translator)

### Compilation
Use the provided `Makefile` to assemble the OS:

```bash
# Assemble the kernel
make
```

### Running
Execute the compiled binary on the SysVM:
```bash
make run
# or
sysvm sysdos.bin
```

<br>


---
## 🤓 How this "rock" works

### ⚙️ Kernel
The kernel is the system's core, responsible for low-level memory management and hardware abstraction.

```asm
; --------------------------------------------
; Memory Plan (RAM Size: 1,048,576 bytes)
;
; [0 - 65,535]               Kernel & OS Binary (Code area) - 64KB
; [65,536 - 67,583]          Syscall Jump Table - 2KB
; [67,584 - 69,991]          Registry Backups Area
; [69,992 - 70,000]          Kernel Specials (Fixed Area)
;
; [70,000 - 800,000]         OS Dynamic Area (Heap / Kalloc Zone) - 730KB
; [800,001 - 999,964]        Disk Buffer Area - 199,964 bytes
; [999,965 - 1,000,000]      Loader Register Save Area - 36 bytes
; [1,000,001 - 1,048,576]    System Stack (Hardware Pb) - 48KB
;
; Fixed Kernel Addresses:
; 69,992 = Heap Pointer (32-bit)
; 69,996 = Error Code   (32-bit)
; --------------------------------------------
```

#### 🚨 Error Codes & Panic
If the kernel hits a limit, it triggers a `kernelPanic`, saving the code to address `69,996` and halting with a register dump.
| Name | Code | Trigger |
|:-----|:-----|:--------|
| Buffer Overflow | 8 | `kalloc` exceeds `800,000` |
| Buffer Underflow | 16 | `kfree` goes below `70,000` |

---

### ⚙️ Kernel API (Syscall Jump Table)
To allow external programs to call Kernel functions without hardcoding internal addresses, SysDOS uses a **Jump Table** starting at `65,536`. Each entry is a 5-byte `JMP <address>` instruction.

**Standard Table Indices:**
1. `65,536`: `KALLOC`
2. `65,541`: `KFREE`
3. `65,546`: `PUTSTR`
4. `65,551`: `STRCMP`
5. `65,556`: `STACKCPY`

---

### 🧠 Memory Management (`kalloc` / `kfree`)

Unlike standard systems, this kernel uses a **Stack-based Heap Pointer** for speed.

*   **`kalloc`:** 
    *   Takes the requested size in register `c`.
    *   Adds `c` to the current **Heap Pointer** (stored at `69,992`).
    *   Returns the address of the allocated block.
*   **`kfree`:** 
    *   Performs the inverse: subtracts the size `c` from the Heap Pointer.
    *   *Note: Memory must be freed in the exact reverse order it was allocated.*

---

### 💻 Operating System (Sysdos)
The OS provides the high-level logic and the user interface through **Syssh**.

#### 🐚 The Shell (Syssh)
The shell runs a loop that:
1.  Displays the `>> `  prompt.
2.  Uses the `IN` opcode (`0x42`) to wait for user input.
3.  **Dynamic Allocation:** Calls `kalloc` (size `1,024`) to create a temporary buffer for the input string.
4.  **Command Parsing:**
    *   Checks for built-ins (`exit`, `shutdown`, `restart`, `cls`) using `strcmp`.
    *   If not found, it prepends `./sysdos/bin/` to the input and calls the **Loader**.
5.  **Cleanup:** Always calls `kfree` after a command cycle to prevent memory leaks in the OS area.

---

### 📂 Program Loader
The Loader is the bridge between the disk and the CPU.

*   **Loading Process:** 
    *   Uses `LOADF` (`0x44`) to load the binary into address `800,000`.
    *   Saves the current shell state (registers `h` to `o`) in the **Register Save Area** (`999,965`) before switching contexts.
*   **Validation (Magic Number):** 
    *   It checks the first 4 bytes for the value **`3301`** (`0xE5 0x0C 0x00 0x00`).
    *   If the magic number is missing, it aborts execution with an "invalid format" message.
*   **Execution:** 
    *   **Registers Reset:** All registers are zeroed out to ensure a clean state for the external program.
    *   **Jump:** The OS calls address **`800,004`** (skipping the 4-byte magic number header).

---

### 🛠️ Technical Reference: Opcodes

| Opcode | Mnemonic | Description |
|:-------|:---------|:------------|
| `0x42` | `IN` | Captures input string from the user. |
| `0x44` | `LOADF` | Loads file to memory. Register `h` returns status (< 0 on error). |

---


<p align="center">
  Developed by <a href="https://github.com/Artxzzzz">Artxzzzz</a><br>
</p>