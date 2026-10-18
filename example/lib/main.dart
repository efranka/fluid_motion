import 'package:flutter/material.dart';
import 'package:fluid_motion/fluid_motion.dart';

import 'bottom_bar/program_screen.dart';
import 'shapes/shapes_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The GPU version of the gooey neck. If it fails, the CPU version is used
  // automatically.
  await GooeyShader.load();
  runApp(const FluidMotionDemo());
}

class FluidMotionDemo extends StatelessWidget {
  const FluidMotionDemo({super.key});

  @override
  Widget build(BuildContext context) => MotionScope(
        // One place to tune the whole app's "material" (springs, press,
        // timings).
        tokens: MotionTokens.standard,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'fluid_motion',
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFFCBC3F5),
              brightness: Brightness.dark,
            ),
          ),
          home: const DemoHome(),
        ),
      );
}

/// Picks a demo.
class DemoHome extends StatelessWidget {
  const DemoHome({super.key});

  @override
  Widget build(BuildContext context) {
    Widget entry(String title, String subtitle, IconData icon, Widget page) =>
        Card(
          child: ListTile(
            leading: Icon(icon),
            title: Text(title),
            subtitle: Text(subtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => page),
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('fluid_motion')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          entry(
            'Bottom bar',
            'Scroll: the tab bar folds into a bubble next to the navigation '
                'bar – springs, arcs, gooey and impact.',
            Icons.view_agenda_outlined,
            const ProgramScreen(),
          ),
          entry(
            'Shapes',
            'Drag circles, stars, rings and more into each other and throw '
                'them back home.',
            Icons.category_outlined,
            const ShapesScreen(),
          ),
        ],
      ),
    );
  }
}
