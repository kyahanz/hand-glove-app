
import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import 'practice_screen.dart';

class LearningScreen extends StatelessWidget {
  const LearningScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Mode Belajar"),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader("Dasar"),
            const SizedBox(height: 16),
            _buildGrid(context, ["A", "B", "C", "D", "E"]),
            
            const SizedBox(height: 32),
            _buildSectionHeader("Angka"),
            const SizedBox(height: 16),
            _buildGrid(context, ["1", "2", "3", "4", "5"]),
            
            const SizedBox(height: 32),
            _buildSectionHeader("Kata Umum"),
            const SizedBox(height: 16),
            _buildWordList(context, ["Halo", "Terima Kasih", "Ya", "Tidak"]),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: AppTheme.secondaryColor,
      ),
    );
  }

  Widget _buildGrid(BuildContext context, List<String> items) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return _buildCard(context, items[index]);
      },
    );
  }

  Widget _buildWordList(BuildContext context, List<String> items) {
     return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          child: ListTile(
            title: Text(items[index], style: const TextStyle(fontWeight: FontWeight.bold)),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white54),
            onTap: () {
               Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => PracticeScreen(target: items[index])),
              );
            },
          ),
        );
      },
     );
  }

  Widget _buildCard(BuildContext context, String title) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PracticeScreen(target: title)),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
          boxShadow: [
             BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 5),
             )
          ],
        ),
        child: Center(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
