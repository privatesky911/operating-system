#!/bin/bash
#

rm -f output/build/linux-6.18.40/.stamp_configured
rm -f output/build/linux-6.18.40/.stamp_built
rm -f output/images/rk3566-odroid-m1s.dtb

./scripts/enter.sh make -j12 odroid_m1s

