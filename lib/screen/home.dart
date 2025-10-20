import 'package:alarm_khamsat/screen/alarm/alarm.dart';
import 'package:alarm_khamsat/screen/clock/clock.dart';
import 'package:alarm_khamsat/screen/stopwatch/stopwatch.dart';
import 'package:alarm_khamsat/screen/timer/timer.dart';
import 'package:animated_bottom_navigation_bar/animated_bottom_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

import '../common/color.dart';
import '../model/clock_model.dart';

final List<String> _navNames = ["Alarm", "Clock", "Timer", "StopWatch"]; 

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  VoidCallback? _onAddAlarm;
  VoidCallback? _onAddClock;
  VoidCallback? _onAddTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration:  Durations.extralong2,animationBehavior: AnimationBehavior.preserve);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int _bottomNavIndex = 0;

  final iconList = [
    "assets/svg/alarm-clock.svg",
    "assets/svg/clock.svg",
    "assets/svg/hourglass.svg",
    "assets/svg/stopwatch.svg",
  ];


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: _bottomNavIndex != 3? FloatingActionButton(
        onPressed: () {
          switch (_bottomNavIndex) {
            case 0:
              if (_onAddAlarm != null) {
                _onAddAlarm!();
              }
              break;
            case 1:
              if (_onAddClock != null) {
                _onAddClock!();
              }
              break;
            case 2:
              if (_onAddTimer != null) {
                _onAddTimer!();
              }
              break;
            default:
              return;
              showModalBottomSheet(
                context: context,
                builder: (ctx) => Container(
                  padding: const EdgeInsets.all(20),
                  height: 160,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('No quick action available', style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      Text('Switch to Clock or Timer to add new items.'),
                    ],
                  ),
                ),
              );
          }
        },
        child: Icon(Icons.add, color: AppColor.scafoldBgColor, size: 25),
        shape: OutlineInputBorder(
          borderRadius: BorderRadius.circular(1000),
          borderSide: BorderSide.none,
        ),
      ): null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,

      bottomNavigationBar: AnimatedBottomNavigationBar.builder(
        itemCount: iconList.length,
        height: 72,

        tabBuilder: (int index, bool isActive) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SvgPicture.asset(
                iconList[index],
                width: 25,
                height: 25,
                fit: BoxFit.scaleDown,
                color: isActive ? AppColor.primaryColor : null,
              ),
              SizedBox(height: 5),
              Text(
                _navNames[index],
                style: TextStyle(
                  color: isActive ? AppColor.primaryColor : null,
                ),
              ),
            ],
          );
        },

        backgroundColor: AppColor.bottomBgColor,
        activeIndex: _bottomNavIndex,
        gapLocation: _bottomNavIndex ==3 ? GapLocation.none: GapLocation.center,
        notchSmoothness: NotchSmoothness.smoothEdge,
        leftCornerRadius: 0,
        rightCornerRadius: 0,
        hideAnimationCurve: ElasticInOutCurve(),
        onTap: (index) => setState(() => _bottomNavIndex = index),
        //other params
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 15, vertical: 20),
          child: IndexedStack(
            index: _bottomNavIndex,
            children: [
              AlarmPage(
                onRegisterAddHandler: (cb) => _onAddAlarm = cb,
              ),
              ClocksPage(
                onRegisterAddHandler: (cb) => _onAddClock = cb,
              ),
              TimerPage(
                onRegisterAddHandler: (cb) => _onAddTimer = cb,
              ),
              const StopwatchPage(),
            ],
          ),
        ),
      ),
    );
  }

}
