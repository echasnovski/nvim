#! /bin/bash

# WARNING: EXECUTION OF THIS SCRIPT LEADS TO FLICKERING OF SCREEN WHICH WHICH MAY
# CAUSE HARM TO YOUR HEALTH. This is because every 'init' file leads to an
# actual opening of Neovim with later automatic closing.

# touch startup-times.csv
#
# function join_by_comma { local IFS=","; shift; echo "$*"; }

function benchmark {
  echo -n "$1: "

  nvim -u init-files/$1 --startuptime tmp-bench.txt

  # Take the total startup time and add it to output csv file
  t=$(tail -n 1 tmp-bench.txt | cut -d " " -f1)
  # sed -i -e '$a'"$t" startup-times.csv
  # sed '$s/$/'"$t"'/' startup-times.csv

  # Remove Neovim's startuptime file
  rm tmp-bench.txt

  echo $t
}

benchmark init_starter-default.lua
benchmark init_empty.lua

benchmark init_starter-startify.lua
benchmark init_startify.lua
benchmark init_alpha-startify.lua

benchmark init_starter-dashboard.lua
benchmark init_dashboard.lua
benchmark init_alpha-dashboard.lua

# time_arr=()
#
# time_arr[0]=$(benchmark init_starter-default.lua)
# time_arr[1]=$(benchmark init_empty.lua)
# time_arr[2]=$(benchmark init_starter-startify.lua)
# time_arr[3]=$(benchmark init_startify.lua)
# time_arr[4]=$(benchmark init_alpha-startify.lua)
# time_arr[5]=$(benchmark init_starter-dashboard.lua)
# time_arr[6]=$(benchmark init_dashboard.lua)
# time_arr[7]=$(benchmark init_alpha-dashboard.lua)
#
# echo $time_arr
