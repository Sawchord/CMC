#!/usr/bin/python2
import time
import sys
from TOSSIM import *

def main():

    sim = Tossim([])
    sim.addChannel("BlinkToRadioC", sys.stdout)
    
    node8 = sim.getNode(8)
    node13 = sim.getNode(13)
    
    node8.bootAtTime(357)
    node13.bootAtTime(3434)
    
    radio = sim.radio()
    link = radio.add(8, 13, 0.0)
    
    
    
    while node8.isOn and node13.isOn:
        sim.runNextEvent()


if __name__ == "__main__":
    sys.exit(main())