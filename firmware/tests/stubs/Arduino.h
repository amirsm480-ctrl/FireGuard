#pragma once
#include <cstdint>
#include <cstddef>
#include <string>
#include <cstring>
#include <algorithm>
#include <array>
#define LOW 0
#define HIGH 1
#define INPUT_PULLUP 2
#define OUTPUT 3
#define INPUT 4
#define ADC_11db 0
#define CONFIG_BLUEDROID_ENABLED 1
#define portENTER_CRITICAL(x) ((void)0)
#define portEXIT_CRITICAL(x) ((void)0)
#define portMUX_INITIALIZER_UNLOCKED 0
using portMUX_TYPE = int;
inline uint32_t simulatedTime = 100;
inline unsigned long echoPulse = 6000;
inline std::array<int,40> gpio{};
inline std::array<int,16> duty{};
inline uint32_t millis() { return simulatedTime; }
inline void delay(unsigned long ms) { simulatedTime += ms; }
inline void delayMicroseconds(unsigned int) {}
inline void digitalWrite(int pin,int value) { gpio[pin]=value; }
inline int digitalRead(int pin) { return gpio[pin]; }
inline void pinMode(int pin,int mode) { if(mode==INPUT_PULLUP)gpio[pin]=HIGH; }
inline unsigned long pulseIn(int,int,unsigned long) { return echoPulse; }
inline int analogRead(int) { return 400; }
inline void analogReadResolution(int) {}
inline void analogSetPinAttenuation(int,int) {}
inline bool ledcAttachChannel(int,int,int,int) { return true; }
inline void ledcWriteChannel(int channel,uint32_t value) { duty[channel]=value; }
template<class T> inline T constrain(T x,T a,T b) { return std::min(b,std::max(a,x)); }
struct SerialStub { void begin(int){}; void println(const char*){}; };
inline SerialStub Serial;
