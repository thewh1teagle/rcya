import 'package:flutter/material.dart';
import 'dart:async';
import 'package:telephony/telephony.dart';
import 'package:carp_background_location/carp_background_location.dart';
import 'dart:io';
import 'package:battery/battery.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

Future<void> onMessage(SmsMessage message) async {
  print('message not background..');
  SharedPreferences prefs = await SharedPreferences.getInstance();
  String phoneNum = prefs.getString('number') ?? '';
  String secret = prefs.getString('secret') ?? '';
  handleMessage(message, phoneNum, secret);
}

Future<void> onBackgroundMessage(SmsMessage message) async {
  print('background message');
  SharedPreferences prefs = await SharedPreferences.getInstance();
  String phoneNum = prefs.getString('number') ?? '';
  String secret = prefs.getString('secret') ?? '';
  print('phone num $phoneNum secret $secret');
  handleMessage(message, phoneNum, secret);
}

Future<void> sendLocation(dstAddr) async {
  var result = await getLocation();
  String long = result.longitude.toString();
  String lat = result.latitude.toString();
  Telephony.instance
      .sendSms(to: dstAddr, message: 'https://maps.google.com/?q=$lat,$long');
}

Future<void> handleMessage(SmsMessage message, secretPhone, secretWord) async {
  String text = message.body!;
  String addr = message.address!;

  if (!isSameNumber(addr, secretPhone) || !text.contains(secretWord))
    return; // secret & phone num validation

  switch (text.split(' ')[0]) {
    case 'location':
      {
        sendLocation(addr);
        break;
      }
    case 'call':
      {
        callNumber(addr);
        break;
      }
    case 'battery':
      {
        sendBattery(addr);
        break;
      }
    case 'commands':
      {
        Telephony.instance.sendSms(to: addr, message: '''
            1. location
            2.battery
            3. call
            4. commands
        ''');
      }
  }
}

Future<String> batteryLevel() async {
  var _battery = Battery();
  // Access current battery level
  int batteryLevel = await _battery.batteryLevel;
  String batteryLevelStr = batteryLevel.toString();
  return batteryLevelStr;
}

Future<void> sendBattery(dstAddr) async {
  String batteryLevelStr = await batteryLevel();
  Telephony.instance.sendSms(to: dstAddr, message: '$batteryLevelStr%');
}

Future<void> callNumber(number) async {
  // am start -a android.intent.action.CALL -d tel:+CCXXXXXXXXXX
  await Process.run('su', [
    '-c',
    'am',
    'start',
    '-a',
    'android.intent.action.CALL',
    '-d',
    'tel:$number'
  ]);
}

bool isSameNumber(String num0, String num1) {
  return num0.contains(num1.substring(1)) || num1.contains(num0.substring(1));
}

Future<LocationDto> getLocation() async {
  await setGps(true);
  LocationDto dto = await LocationManager().getCurrentLocation();
  await setGps(false);
  return dto;
}

Future<void> setGps(bool state) async {
  var result = await Process.run('su',
      ['-c', 'settings', 'put', 'secure', 'location_mode', state ? '3' : '0']);
}

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final telephony = Telephony.instance;
  final phoneNumController = TextEditingController();
  final secretController = TextEditingController();
  String secret = '';
  String phoneNum = '';
  bool? switchState;

  @override
  void initState() {
    super.initState();
    initApp();
  }

  // onMessage(SmsMessage message) async {
  //   print('message not background..');
  //   handleMessage(message, phoneNum, secret);
  // }

  // void onBackgroundMessage(SmsMessage message) {
  //   print('background message');
  //   print(message.address);
  //   handleMessage(message, phoneNum, secret);
  // }

  setSmsListenerState(bool state) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setBool('state', switchState ?? false);
    final bool? result = await telephony.requestPhoneAndSmsPermissions;

    if (result != null && result && state) {
      telephony.listenIncomingSms(
          onNewMessage: onMessage, onBackgroundMessage: onBackgroundMessage);
    } else if (result != null && state == false) {
      telephony.listenIncomingSms(
          onNewMessage: (SmsMessage message) {}, listenInBackground: false);
    }
  }

  initApp() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    phoneNum = prefs.getString('number') ?? '';
    secret = prefs.getString('secret') ?? '';
    setState(() {
      switchState = prefs.getBool('state');
      if (switchState == null) {
        switchState = false;
      }
    });
  }

  Future<void> handleSaveButton() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setString('number', phoneNumController.text);
    prefs.setString('secret', secretController.text);
    setState(() {
      phoneNum = phoneNumController.text;
      secret = secretController.text;
      phoneNumController.text = '';
      secretController.text = '';
    });
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  void dispose() {
    // Clean up the controller when the widget is disposed.
    phoneNumController.dispose();
    secretController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        home: Scaffold(
      appBar: AppBar(
        title: const Text('rcya'),
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            child: Center(
              child: Text(
                'Remote control your android',
                style: TextStyle(fontSize: 30, color: Colors.lightBlue),
              ),
            ),
            padding: EdgeInsets.all(40),
          ),
          Container(
            child: Center(
              child: Text(
                '1. Choose phone number and secret word\n2. turn on the switch\n3. send the word "commands (secret)"\n    in sms to this number',
                textAlign: TextAlign.left,
              ),
            ),
            padding: EdgeInsets.only(bottom: 40),
          ),
          Center(
            child: Switch(
                value: switchState ?? false,
                onChanged: (value) {
                  setSmsListenerState(value);
                  setState(() {
                    switchState = value;
                  });
                }),
          ),
          Container(
            child: TextField(
              decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: phoneNum,
                  labelText: 'Phone'),
              controller: phoneNumController,
            ),
            padding: EdgeInsets.only(left: 20, right: 20, bottom: 10),
          ),
          Container(
            child: TextField(
              decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: secret,
                  labelText: 'Secret'),
              controller: secretController,
            ),
            padding: EdgeInsets.only(left: 20, right: 20, bottom: 10),
          ),
          ElevatedButton(
              onPressed: handleSaveButton,
              child: Padding(
                padding:
                    EdgeInsets.only(left: 18, right: 18, top: 3, bottom: 3),
                child: Text(
                  'Save',
                  style: new TextStyle(fontSize: 22),
                ),
              )),
        ],
      ),
    ));
  }
}
