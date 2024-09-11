# Multithreaded 2-Way Superscalar LEGv8 Processor with Out-of-Order Execution and Register Renaming

## Project Overview

This project focuses on designing and implementing a **Multithreaded 2-Way Superscalar LEGv8 Processor**. The processor is capable of processing **four threads** concurrently, with each thread able to execute **two instructions at a time**. Key architectural features include **Out-of-Order (OoO) execution**, **register renaming**, and a series of optimizations essential for efficient multithreaded processing.

The goal of the project is to tape out the final CPU design using the **Tiny Tapeout service**, a platform that facilitates small-scale IC fabrication.

## Key Features and Goals

### 1. **Multithreading and 2-Way Superscalar Execution**
- **Multithreading**: The processor will handle **four threads** simultaneously, with each thread running independently and processing its own instruction stream.
- **2-Way Superscalar**: Each thread is designed to fetch and execute **two instructions in parallel**, allowing a total of **eight instructions** to be processed per clock cycle across all threads.

### 2. **Out-of-Order (OoO) Execution**
The CPU supports **Out-of-Order (OoO)** execution to maximize performance by dynamically reordering instructions. Instructions are executed as soon as their operands are available, reducing pipeline stalls due to dependencies or earlier instructions.

### 3. **Register Renaming**
To handle **data hazards**, **register renaming** will be used. A set of physical registers will be allocated to avoid conflicts between multiple instructions executing in parallel, which helps resolve **WAR (Write-After-Read)** and **WAW (Write-After-Write)** hazards.

### 4. **Dynamic Instruction Scheduling**
- **Instruction Scheduling**: The CPU will use dynamic scheduling techniques like **Scoreboarding** or **Tomasulo’s Algorithm** to track dependencies and ensure that ready instructions are executed while minimizing pipeline stalls.
- The processor will **analyze dependencies** and issue instructions that can be executed without conflicts in parallel.

### 5. **Dependency Management and Parallel Execution**
- **Instruction Fetch**: Instructions are fetched in parallel for each thread, keeping the pipeline full and ensuring maximum throughput.
- **Dependency Resolution**: The CPU analyzes instructions in each thread to determine **independent instructions** that can be executed in parallel. This avoids unnecessary stalling and ensures high utilization of resources.
- **Branch Prediction**: A branch prediction mechanism is included to minimize pipeline stalls from control hazards.

### 6. **Tiny Tapeout Goal**
- The design will be fabricated using the **Tiny Tapeout** platform, allowing for the design to be produced as an **integrated circuit**.
- The design will be verified via **FPGA simulation** before submission for tapeout, ensuring functionality and performance are optimized before fabrication.

## Fetch and Execute Process

### Fetch Stage:
The processor fetches **two instructions per thread** in each cycle. The **instruction fetch unit** handles the program counter (PC) for each thread and updates it based on branch prediction outcomes. This keeps the pipeline filled with instructions, reducing stalls.

### Decode and Issue:
The CPU decodes instructions in parallel, identifying **instruction-level parallelism (ILP)** and determining if two instructions can execute simultaneously. Independent instructions are issued for execution immediately, while dependent instructions are held back until their operands are ready.

### Execute:
During execution, the **register renaming** mechanism ensures that instructions can use registers without conflicts. The CPU resolves **data hazards** using techniques like **bypassing** and **forwarding** to minimize pipeline stalls.

### Commit:
Instructions are **retired** in the correct order, with results being written back to the correct registers. **Precise exception handling** is ensured through this process.

## Conclusion

This project implements a state-of-the-art multithreaded, 2-way superscalar processor based on the LEGv8 architecture. Combining multithreading, superscalar execution, and advanced techniques like **OoO execution** and **register renaming**, the design aims to provide a high-performance processing solution capable of handling up to **eight instructions per cycle** across four threads.

After simulation and verification, the design will be submitted for **tapeout** using Tiny Tapeout, turning this digital design into a physical IC.


