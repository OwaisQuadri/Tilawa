#!/bin/bash
# Find downloaded mushaf PDFs in the simulator's Documents directory
find ~/Library/Developer/CoreSimulator/Devices -path "*/Documents/MushafPDFs/*.pdf" 2>/dev/null
