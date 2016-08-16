#ifndef CMC_TEST_H
#define CMC_TEST_H

#define STEPPING 100
#define AM_SENSOR_CHANNEL 6

typedef nx_struct SensorMsg {
    nx_uint16_t nodeid;
    nx_uint16_t temp;
    nx_uint8_t lum;
} SensorMsg;


#endif /* CMC_TEST_H */