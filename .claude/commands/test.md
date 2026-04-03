Build the screen saver and run the memory leak test.

Steps:
1. Run `bash build.sh` to compile
2. Run `bash test_memory.sh --build` to install and run memory tests (5x cycle + 30s steady-state)
3. Report results — all 4 tests must PASS