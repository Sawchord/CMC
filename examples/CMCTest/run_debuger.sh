#!/bin/bash
echo 'Bulding the binary'
make iris debug

echo 'Loading the binary onto USB0'
make iris reinstall.0 mib520,/dev/ttyUSB0

echo 'Setting fuse bit for debug'
sleep 1
avrdude -cmib510 -P/dev/ttyUSB0 -U hfuse:w:0x19:m -pm1281

echo 'Starting avarice'
echo $'You may run \'ddd --debugger \"avr-gdb -x gdb.conf\" \' now '

sleep 1
avarice -g -j usb localhost:4242
