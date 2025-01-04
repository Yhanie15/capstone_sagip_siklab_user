import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  // Method to open a URL
  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      throw 'Could not launch $url';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          "Privacy Policy",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Center(
              child: Column(
                children: [
                  const Text(
                    "Privacy Policy",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFB71C1C),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Effective Date:  January 2024",
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => _launchUrl("https://example.com"),
                    child: const Text(
                      "Click here to learn more",
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.blue,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 30, color: Colors.grey),

             // Contact Us Section
            const Text(
              "Contact Us",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "If you have questions about data protection, or if you have any requests for resolving issues with your personal data, we encourage you to contact us through email so we can reply to you more quickly.",
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              "Name of Controller: Quezon City Fire District",
              style: TextStyle(fontSize: 16),
            ),
            const Text(
              "Address: Hall Compound, Kalayaan Ave, Diliman, Quezon City, 1100 Metro Manila",
              style: TextStyle(fontSize: 16),
            ),
            const Text(
              "Contact Number: 8330-2344 / 0968-883-4546",
              style: TextStyle(fontSize: 16),
            ),
            const Divider(height: 30, color: Colors.grey),

            // The Data We Collect Section
            const Text(
              "The Data We Collect",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "• Contact Information (such as name, email address, and contact number) to establish your identity in reporting emergencies.",
              style: TextStyle(fontSize: 16),
            ),
            const Text(
              "• Profile Information (such as profile photo).",
              style: TextStyle(fontSize: 16),
            ),
            const Text(
              "• Your messages to the Service (such as text messages).",
              style: TextStyle(fontSize: 16),
            ),
            const Text(
              "• Other data you choose to give us (such as report images and location).",
              style: TextStyle(fontSize: 16),
            ),
            const Divider(height: 30, color: Colors.grey),

            // Why Do We Collect Your Data Section
            const Text(
              "Why Do We Collect Your Data",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "To make the service work. To perform the services, we process data necessary to:",
              style: TextStyle(fontSize: 16),
            ),
            const Text(
              "• Create accounts and allow you to use our services.",
              style: TextStyle(fontSize: 16),
            ),
            const Text(
              "• Operate the service.",
              style: TextStyle(fontSize: 16),
            ),
            const Text(
              "• Prevent prank reports.",
              style: TextStyle(fontSize: 16),
            ),
            const Text(
              "• Provide and deliver services you request.",
              style: TextStyle(fontSize: 16),
            ),
            const Text(
              "• Send you service-related communications.",
              style: TextStyle(fontSize: 16),
            ),
            const Divider(height: 30, color: Colors.grey),

            // Who Can See Your Data Section
            const Text(
              "Who Can See Your Data",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Quezon City Fire District and its Responding Units.",
              style: TextStyle(fontSize: 16),
            ),
            const Divider(height: 30, color: Colors.grey),

            // Your Rights and Options Section
            const Text(
              "Your Rights and Options",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "SagipSiklab will never send you any promotional communications, such as marketing emails not related to our service.",
              style: TextStyle(fontSize: 16),
            ),
            const Text(
              "If you request, we will provide you a copy of your personal data in an electronic format.",
              style: TextStyle(fontSize: 16),
            ),
            const Text(
              "You also have the right to correct your data, have your data deleted, object how we use or share your data, and restrict how we use or share your data. You can always withdraw your consent, for example by turning off GPS location in your mobile device settings but this will hamper the very purpose of our services.",
              style: TextStyle(fontSize: 16),
            ),
            const Divider(height: 30, color: Colors.grey),

            // Disclaimer Section
            const Text(
              "Disclaimer",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "The picture you uploaded on this application will undergo verification as per the standard operating procedure in responding to a fire or any emergency call. Whilst, Quezon City Fire District will use reasonable efforts in doing the same in the most expedient and effective way.",
              style: TextStyle(fontSize: 16),
            ),
            const Text(
              "Further, Quezon City Fire District accepts no responsibility or liability for the false information uploaded by the users. Under no circumstances will Quezon City Fire District be held responsible or liable in any way for any damages, losses or whatsoever resulting or arising directly or indirectly by reason thereof.",
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                ),
                child: const Text(
                  "ACCEPT",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
