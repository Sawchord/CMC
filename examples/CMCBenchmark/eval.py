#!/usr/bin/python3

import sys

if (len(sys.argv) != 3):
  print("Usage:" + sys.argv[0] + " input output")

i = sys.argv[1]
o = sys.argv[2]


with open(i , 'r') as myfile:
    data=myfile.read()

dsplit = data.split('\n')


occur = [0] * 200
count = [0] * 200

for d in dsplit:
  e = d.split(' ')
  
  if (len(e) <= 4):
    continue
  
  occur[int(e[2])] += 1
  count[int(e[2])] += int(e[4])

with open(o, 'w') as myfile:
  for i in range(0,200):
    if (occur[i] != 0):
      myfile.write(str(i) + ' ' + str(count[i]/occur[i]) + '\n')