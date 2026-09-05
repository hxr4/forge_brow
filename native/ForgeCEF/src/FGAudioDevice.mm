#import "FGAudioDevice.h"

#import <CoreAudio/CoreAudio.h>

namespace {

NSString* TransportName(UInt32 transport) {
  switch (transport) {
    case kAudioDeviceTransportTypeBuiltIn: return @"Built-in";
    case kAudioDeviceTransportTypeUSB: return @"USB";
    case kAudioDeviceTransportTypeBluetooth: return @"Bluetooth";
    case kAudioDeviceTransportTypeBluetoothLE: return @"Bluetooth LE";
    case kAudioDeviceTransportTypeHDMI: return @"HDMI";
    case kAudioDeviceTransportTypeDisplayPort: return @"DisplayPort";
    case kAudioDeviceTransportTypeAirPlay: return @"AirPlay";
    case kAudioDeviceTransportTypeAggregate: return @"Aggregate";
    case kAudioDeviceTransportTypeVirtual: return @"Virtual";
    case kAudioDeviceTransportTypeThunderbolt: return @"Thunderbolt";
    case kAudioDeviceTransportTypeFireWire: return @"FireWire";
    case kAudioDeviceTransportTypePCI: return @"PCI";
    default: return @"Unknown";
  }
}

}  // namespace

@implementation FGAudioDevice

+ (NSDictionary<NSString *, id> *)currentOutput {
  AudioObjectPropertyAddress address = {
    kAudioHardwarePropertyDefaultOutputDevice,
    kAudioObjectPropertyScopeGlobal,
    kAudioObjectPropertyElementMain
  };

  AudioDeviceID device = kAudioObjectUnknown;
  UInt32 size = sizeof(device);
  if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, &device) != noErr ||
      device == kAudioObjectUnknown) {
    return @{};
  }

  NSMutableDictionary<NSString *, id>* result = [NSMutableDictionary dictionary];

  CFStringRef name = NULL;
  size = sizeof(name);
  address.mSelector = kAudioObjectPropertyName;
  address.mScope = kAudioObjectPropertyScopeGlobal;
  if (AudioObjectGetPropertyData(device, &address, 0, NULL, &size, &name) == noErr && name) {
    result[@"name"] = (__bridge_transfer NSString*)name;
  }

  Float64 rate = 0;
  size = sizeof(rate);
  address.mSelector = kAudioDevicePropertyNominalSampleRate;
  if (AudioObjectGetPropertyData(device, &address, 0, NULL, &size, &rate) == noErr) {
    result[@"sampleRate"] = @(rate);
  }

  UInt32 transport = 0;
  size = sizeof(transport);
  address.mSelector = kAudioDevicePropertyTransportType;
  if (AudioObjectGetPropertyData(device, &address, 0, NULL, &size, &transport) == noErr) {
    result[@"transport"] = TransportName(transport);
  }

  AudioStreamBasicDescription format;
  memset(&format, 0, sizeof(format));
  size = sizeof(format);
  address.mSelector = kAudioStreamPropertyVirtualFormat;
  address.mScope = kAudioObjectPropertyScopeOutput;
  if (AudioObjectGetPropertyData(device, &address, 0, NULL, &size, &format) == noErr) {
    result[@"mixDepth"] = @(format.mBitsPerChannel);
    result[@"channels"] = @(format.mChannelsPerFrame);
  }

  AudioStreamBasicDescription physical;
  memset(&physical, 0, sizeof(physical));
  size = sizeof(physical);
  address.mSelector = kAudioStreamPropertyPhysicalFormat;
  address.mScope = kAudioObjectPropertyScopeOutput;
  if (AudioObjectGetPropertyData(device, &address, 0, NULL, &size, &physical) == noErr &&
      physical.mBitsPerChannel > 0) {
    result[@"bitDepth"] = @(physical.mBitsPerChannel);
    const bool isFloat = (physical.mFormatFlags & kAudioFormatFlagIsFloat) != 0;
    result[@"sampleFormat"] = isFloat ? @"float" : @"integer";
  }

  address.mSelector = kAudioDevicePropertyAvailableNominalSampleRates;
  address.mScope = kAudioObjectPropertyScopeGlobal;
  size = 0;
  if (AudioObjectGetPropertyDataSize(device, &address, 0, NULL, &size) == noErr && size > 0) {
    AudioValueRange* ranges = (AudioValueRange*)malloc(size);
    if (ranges) {
      const UInt32 count = size / (UInt32)sizeof(AudioValueRange);
      if (AudioObjectGetPropertyData(device, &address, 0, NULL, &size, ranges) == noErr) {
        NSMutableArray<NSNumber *>* rates = [NSMutableArray array];
        for (UInt32 index = 0; index < count; index++) {
          [rates addObject:@(ranges[index].mMaximum)];
        }
        result[@"availableRates"] = rates;
      }
      free(ranges);
    }
  }

  return result;
}

@end
