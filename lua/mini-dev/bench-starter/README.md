# Benchmarks for 'mini.starter'

This directory contains code and results of benchmarking 'mini.starter' and its alternatives. Target benchmarked value is a total startup time using configuration file (with `-u <init-file>`) corresponding to benchmarked setup. Configuration files are created in three different groups:

- 'init_starter-default.lua' and 'init_empty.lua' represent default 'mini.starter' setup and corresponding 'init.lua' without 'mini.starter'.
- 'init_startify-starter', 'init_startify-original', and 'init_startify-alpha' have comparable output imitating default 'vim-startify' with empty header.
- 'init_dashboard-starter', 'init_dashboard-original', and 'init_dashboard-alpha' have comparable output imitating default 'dashboard-nvim' enabled keybindings.

Summary of startup-times for various 'init' files from 'init-files/' directory can be seen in 'startup-summary.md'.

To rerun locally:

```bash
chmod +x install.sh
./install.sh

# This will create file 'startup-times.csv' and update 'startup-summary.md'
# WARNING: this will lead to screen flicker
chmod +x benchmark.sh
./benchmark.sh
```

Structure:

- 'init-files/' - directory with all configuration files being benchmarked. NOTE: all of them contain auto-closing command at the end (`defer_fn(...)`) to most accurately measure startup time. To view its output, remove this command.
- 'benchmark.sh' - script for performing benchmark which is as close to real-world usage as reasonably possible and computing its summary. Its outputs are 'startup-times.csv' and 'startup-summary.md'. All configuration files are benchmarked in alternate fashion: first 'init' file, second, ..., last, first, etc. WARNING: EXECUTION OF THIS SCRIPT LEADS TO MONITOR FLICKERING WHICH MAY CAUSE HARM TO YOUR HEALTH. This is needed to ensure that Neovim was actually opened and something was drawn.
- 'install.sh' - script for installing all required plugins. NOTE: run `chmod +x install.sh` to make it executable.
- 'startup-times.csv' (ignored by Git) - csv-file with measured startup times. Each row represent single startup round: when all 'init' files are run alternately. Each column represent startup times of single 'init' file.
- 'startup-summary.md' - markdown file as output of 'make_summary.py'. Contains summaries of 'startup-times.csv'.
