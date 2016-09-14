#!/usr/bin/python

from TOSSIM import *
import sys

sim = Tossim([])

sim.addChannel("App", sys.stdout)

node = sim.getNode(1)
node.bootAtTime(1000)


# core loop
while True:
  sim.runNextEvent()