#pragma once
#include "Arduino.h"
struct esp_ble_gatts_cb_param_t {
  struct { uint16_t conn_id; } connect, disconnect, write;
};
class BLEServer;
class BLECharacteristic;
class BLEServerCallbacks {
 public:
  virtual void onConnect(BLEServer*,esp_ble_gatts_cb_param_t*){}
  virtual void onDisconnect(BLEServer*,esp_ble_gatts_cb_param_t*){}
  virtual ~BLEServerCallbacks()=default;
};
class BLECharacteristicCallbacks {
 public:
  virtual void onWrite(BLECharacteristic*,esp_ble_gatts_cb_param_t*){}
  virtual ~BLECharacteristicCallbacks()=default;
};
class BLECharacteristic {
 public:
  static constexpr uint32_t PROPERTY_WRITE=1, PROPERTY_READ=2, PROPERTY_NOTIFY=4;
  std::string value;
  BLECharacteristicCallbacks* callbacks=nullptr;
  void setCallbacks(BLECharacteristicCallbacks* c){callbacks=c;}
  void setValue(uint8_t* bytes,size_t len){value.assign(reinterpret_cast<char*>(bytes),len);}
  std::string getValue(){return value;}
  template<class T> void addDescriptor(T*){}
  void notify(){}
};
class BLEService {
 public:
  BLECharacteristic* createCharacteristic(const char*,uint32_t){return new BLECharacteristic;}
  void start(){}
};
class BLEServer {
 public:
  BLEServerCallbacks* callbacks=nullptr;
  void setCallbacks(BLEServerCallbacks* c){callbacks=c;}
  void disconnect(uint16_t){}
  BLEService* createService(const char*){return new BLEService;}
};
class BLEAdvertising {
 public:
  void addServiceUUID(const char*){}
  void setScanResponse(bool){}
  void setMinPreferred(uint16_t){}
};
class BLEDevice {
 public:
  static void init(const char*){}
  static BLEServer* createServer(){return new BLEServer;}
  static BLEAdvertising* getAdvertising(){return new BLEAdvertising;}
  static void startAdvertising(){}
};
