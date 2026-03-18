import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'signup_page.dart';
import 'home_page.dart';
import 'project_waiting_page.dart';
import 'client_project_page.dart';
import 'contractor_page.dart';
import 'architect_page.dart';
import 'admin_page.dart';


class LoginPage extends StatefulWidget{
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  TextEditingController emailCtrl = TextEditingController();
  TextEditingController passwordCtrl = TextEditingController();

  bool hidePassword = true;
  bool isLoading = false;
  String? selectedRole;
  final List<String> roles = ['Client', 'Contractor', 'Architect', 'Admin'];

  @override
  void dispose() {
    emailCtrl.dispose();
    passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> loginUser() async {
    // Read login form values.
    String email = emailCtrl.text.trim();
    String password = passwordCtrl.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter email and password')),
      );
      return;
    }
    if (selectedRole == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select your role')),
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      // Step 1: Authenticate with Firebase Auth.
      UserCredential userCredential = 
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );

        String uid = userCredential.user!.uid;
        DocumentReference userRef =
            FirebaseFirestore.instance.collection('users').doc(uid);

        await userRef.set({
          'lastLogin': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // Step 2: Read user profile from Firestore (role is stored here).
        DocumentSnapshot userDoc = await userRef.get();

        if (!userDoc.exists || userDoc.data() == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User profile not found')),
          );
          return;
        }

        Map<String, dynamic> userData =
            userDoc.data() as Map<String, dynamic>;
        
        String role = (userData['role'] ?? '').toString();

        if (role.isEmpty) {
          role = selectedRole!;
          await userRef.set({
            'role': role,
          }, SetOptions(merge: true));
        } else if (role != selectedRole) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Selected role does not match account role')),
          );
          return;
        }

        if (!mounted) return;

        // Step 3: Route user by role.
        if (role == 'Client') {
          final destination = await _resolveClientLandingPage(uid);
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => destination),
          );
        } else if (role == 'Contractor') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => ContractorPage()),
          );
        } else if (role == 'Architect') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => ArchitectPage()),
          );
        } else if (role == 'Admin') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => AdminPage()),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User role not found')),
          );
        }
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? "Login failed"),
          ),
      );
    } on FirebaseException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? "Database error"),
          ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Something went wrong"),
          ),
      );
    }
      if (mounted) {
        setState(() {
          isLoading = false;
        });
    }
  }

  Future<Widget> _resolveClientLandingPage(String uid) async {
    final firestore = FirebaseFirestore.instance;
    final bookingSnap = await firestore
        .collection("bookings")
        .where("userId", isEqualTo: uid)
        .get();

    if (bookingSnap.docs.isEmpty) {
      return const HomePage();
    }

    QueryDocumentSnapshot<Map<String, dynamic>>? latestDoc;
    DateTime? latestDate;
    for (final doc in bookingSnap.docs) {
      final data = doc.data();
      final ts = data["createdAt"] as Timestamp?;
      final date = ts?.toDate() ?? DateTime(2000);
      if (latestDate == null || date.isAfter(latestDate)) {
        latestDate = date;
        latestDoc = doc;
      }
    }

    final latest = latestDoc?.data() ?? <String, dynamic>{};
    final accessGranted = latest["accessGranted"] == true;
    if (!accessGranted || latestDoc == null) {
      return const ProjectWaitingPage();
    }

    final projectSnap = await firestore
        .collection('projects')
        .doc(latestDoc.id)
        .get();
    if (!projectSnap.exists) {
      return const ProjectWaitingPage();
    }

    return const ClientProjectPage();
  }

  Future<void> forgotPassword() async {
    String email = emailCtrl.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your email first')),
      );
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password reset link sent to email')),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Failed to send reset email')),
      );
    }
  }

  Widget buildInputBox({
    required IconData icon,
    required TextEditingController controller,
    required String hintText,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFEFEFEF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscureText,
              decoration: InputDecoration(
                hintText: hintText,
                border: InputBorder.none,
                suffixIcon: suffixIcon,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildRoleBox() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFEFEFEF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_outline),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selectedRole,
                hint: const Text('Select your role'),
                isExpanded: true,
                items: roles.map((role) {
                  return DropdownMenuItem<String>(
                    value: role,
                    child: Text(role),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    selectedRole = value;
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFEFF0),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.black,
              child: IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new,
                  color: Colors.white,
                  size: 18,
                ),
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
            ),
            const SizedBox(height: 20),

            const Text(
              "Welcome Back!",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 40),

            Center(
              child: Image.asset(
                'assets/logo.png',
                width: 160,
                fit: BoxFit.contain,
              ),
            ),

            const SizedBox(height: 40),

            buildInputBox(
              icon: Icons.mail_outline,
              controller: emailCtrl,
              hintText: "Enter your email",
            ),

            const SizedBox(height: 14),

            buildInputBox(
              icon: Icons.lock_outline,
              controller: passwordCtrl,
              hintText: "Enter your password",
              obscureText: hidePassword,
              suffixIcon: IconButton(
                icon: Icon(
                  hidePassword ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () {
                  setState(() {
                    hidePassword = !hidePassword;
                  });
                },
              ),
            ),

            const SizedBox(height: 10),

            buildRoleBox(),

            const SizedBox(height: 10),

            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: forgotPassword,
                child: const Text(
                  "Forgot Password?",
                  style: TextStyle(
                    color: Colors.blue ,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: isLoading ? null : loginUser,
                child: isLoading
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    :const Text(
                      "Get Started",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600
                      ),
                    ),
              ),
            ),

            const SizedBox(height: 20,),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  "Don't have an account?",
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),

                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const SignupPage()),
                    );
                  },
                  child: const Text(
                    "Sign Up",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold
                    ),
                  ),
                )
              ],
            )
          ],
        ),
      ),
    );
  }
}
