#!/usr/bin/env python3
#
# Copyright 2021-2025 The ImpactX Community
#
# Authors: Axel Huebl
# License: BSD-3-Clause-LBNL
#
import re
import sys


find = r'name="impactx",'
replace = r'name="impactx-noacc",'


if len(sys.argv) == 2:
    file_path = sys.argv[1]
else:
    print("Must pass path to setup.py as first argument!")
    sys.exit(1)

new_content = ""
with open(file_path, "r") as file:
    for line in file.readlines():
        if re.search(find, line):
            new_content += re.sub(find, replace, line)
        else:
            new_content += line  # Keep original line

with open(file_path, "w") as file:
    file.write(new_content)
