#!/usr/bin/python

from TOSSIM import *

sim = Tossim([])

server = sim.getNode(1)
core = sim.getNode(2)

server.bootAtTime(1000)
core.bootAtTime(300)


# core loop
while True:
  sim.runNextEvent()