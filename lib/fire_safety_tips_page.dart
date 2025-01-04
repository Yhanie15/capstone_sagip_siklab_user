// fire_safety_tips_page.dart

import 'package:flutter/material.dart';

class FireSafetyTipsPage extends StatelessWidget {
  const FireSafetyTipsPage({super.key});

  // A simple list of tips. Each entry has a title, subtitle, asset image, and detail content.
  final List<Map<String, String>> tips = const [
    {
      "title": "BEFORE",
      "subtitle": "What to do BEFORE a fire?",
      "image": "assets/before.png", // Replace with your own image path
      "content": "• Install smoke alarms on every level of your home.\n• Develop and practice a fire escape plan with all family members.\n• Keep flammable materials away from heat sources.\n• Regularly inspect and maintain electrical systems."
    },
    {
      "title": "DURING",
      "subtitle": "What to do DURING a fire?",
      "image": "assets/during.png",
      "content": "• Remain calm and alert.\n• Feel doors for heat before opening them.\n• Get out immediately using the planned escape route.\n• Stay low to avoid smoke inhalation.\n• Once outside, move away from the building and call emergency services."
    },
    {
      "title": "AFTER",
      "subtitle": "What to do AFTER a fire?",
      "image": "assets/after.png",
      "content": "• Call emergency services if you haven't already.\n• Do not re-enter the building until authorities declare it safe.\n• Seek medical attention for any injuries.\n• Document the damage for insurance purposes.\n• Contact support services if you need assistance."
    },
    {
      "title": "FIRE EXTINGUISHER",
      "subtitle": "How to use a FIRE EXTINGUISHER?",
      "image": "assets/extinguisher.png",
      "content": "• P: Pull the pin to break the tamper seal.\n• A: Aim the nozzle at the base of the fire.\n• S: Squeeze the handle to release the extinguishing agent.\n• E: Sweep the nozzle from side to side until the fire is out."
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text("Fire Safety Tips",
        style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ), 
        // The back arrow is automatically included by Flutter when using Navigator.push
      ),
      body: ListView.separated(
        itemCount: tips.length,
        separatorBuilder: (context, index) => const Divider(height: 0),
        itemBuilder: (context, index) {
          final tip = tips[index];
          return ListTile(
            leading: Image.asset(
              tip["image"]!,
              width: 50,
              height: 50,
              fit: BoxFit.cover,
            ),
            title: Text(
              tip["title"]!,
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              tip["subtitle"]!,
              style: const TextStyle(color: Colors.black54),
            ),
            onTap: () {
              // Navigate to a detail page when tapped
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => FireSafetyTipDetailPage(
                    title: tip["title"]!,
                    content: tip["content"]!,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// This is the detail page that shows the full content of a particular tip.
class FireSafetyTipDetailPage extends StatelessWidget {
  final String title;
  final String content;

  const FireSafetyTipDetailPage({
    super.key,
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title), // E.g., "BEFORE"
        // The back arrow is automatically included by Flutter when using Navigator.push
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          content,
          style: const TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}
