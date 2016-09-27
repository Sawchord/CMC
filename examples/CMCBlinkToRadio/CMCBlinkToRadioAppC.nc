#include <Timer.h>
#include "CMCBlinkToRadio.h"

configuration CMCBlinkToRadioAppC {
}
implementation {
    components MainC;
    components LedsC;
    components CMCBlinkToRadioC as App;
    
    components new TimerMilliC() as Timer0;
    components new CMCSocket() as CMC0;
    
    components ActiveMessageC;
    App.RadioControl -> ActiveMessageC;
    
    App.CMC0 -> CMC0;
    
    App.Boot -> MainC;
    App.Leds -> LedsC;
    App.Timer0 -> Timer0;
    
    
    //components SerialStartC;
    //components PrintfC;
}
