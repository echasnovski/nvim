# Benchmarks for 'mini.starter'

This directory contains code and results of benchmarking 'mini.starter' and its alternatives. Target benchmarked value is a total startup time using configuration file (with `-u <init-file>`) corresponding to benchmarked setup.

Structure:

- 'init-files/' - directory with all configuration files being benchmarked. NOTE: all of them contain auto-closing command at the end (`defer_fn(...)`) to most accurately measure startup time. To view its output, remove this command.
- 'benchmark.sh' - script for performing benchmark which is as close to real-world usage as reasonably possible. Its output is 'startup-times.csv'. All configuration files are benchmarked in alternate fashion: first 'init' file, second, ..., last, first, etc. WARNING: EXECUTION OF THIS SCRIPT LEADS TO MONITOR FLICKERING WHICH MAY CAUSE HARM TO YOUR HEALTH. This is needed to ensure that Neovim was actually opened and something was drawn.
- 'startup-times.csv' - csv-file with measured startup times. Each row represent single startup block: when all 'init' files are run alternately. Each column
- 'install.sh' - script for installing all required plugins. NOTE: run `chmod +x install.sh` to make it executable.
- 'uninstall.sh' - script for uninstalling all required plugins. NOTE: run `chmod +x uninstall.sh` to make it executable.
