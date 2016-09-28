#include <Timer.h>
#include "CMCBlinkToRadio.h"

configuration CMCBlinkToRadioAppC {
}
implementation {
    components MainC;
    components LedsC;
    components CMCBlinkToRadioC as App;
    
    components new TimerMilliC() as Timer0;
    
    components ActiveMessageC;
    App.RadioControl -> ActiveMessageC;
    
    // The CMC module
    components new CMCSocket() as CMC0;
    App.CMC0 -> CMC0;
    // CMC needs additional components to work
    components ECCC,NNM, ECIESC;
    App.NN -> NNM;
    
    
    App.Boot -> MainC;
    App.Leds -> LedsC;
    App.Timer0 -> Timer0;
    
    
    components SerialStartC;
    components PrintfC;
}
