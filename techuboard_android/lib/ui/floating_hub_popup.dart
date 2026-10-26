import 'package:flutter/material.dart';

/// A macOS-style contextual popup panel that morphs from the Floating Hub button.
class FloatingHubPopup extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 300,
        height: 400,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.95),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, 10))
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text("Contextual Actions", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ),
            Expanded(
              child: ListView(
                children: [
                  ListTile(leading: Icon(Icons.copy), title: Text("Copy to Device A")),
                  ListTile(leading: Icon(Icons.translate), title: Text("Translate")),
                  ListTile(leading: Icon(Icons.save), title: Text("Save to Notes")),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
