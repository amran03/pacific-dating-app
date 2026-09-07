import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pacific_dating_app/core/constants/app_color.dart';
import 'package:pacific_dating_app/core/services/matchmaking_service.dart';
import 'package:pacific_dating_app/features/profile/data/user_model.dart';
import 'package:pacific_dating_app/features/profile/presentation/public_profile_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final MatchmakingService _matchmakingService = MatchmakingService();

  List<UserModel> _results = [];
  bool _isSearching = false;
  bool _hasSearchedOnce = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // "Debounce" - inasubiri mtumiaji aache kuandika kwa milisekunde 400
  // kabla ya kutafuta, ili tusipige Firestore kila herufi anapoandika.
  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _performSearch(query));
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _isSearching = false;
        _hasSearchedOnce = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _hasSearchedOnce = true;
    });

    try {
      final results = await _matchmakingService.searchUsersByName(query);
      if (mounted) {
        setState(() {
          _results = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSearching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Imeshindikana kutafuta: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Container(
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F8),
            borderRadius: BorderRadius.circular(14),
          ),
          child: TextField(
            controller: _searchController,
            autofocus: true,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: "Tafuta jina la mtumiaji...",
              hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
              prefixIcon: const Icon(Icons.search_rounded, color: Colors.grey, size: 22),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                icon: const Icon(Icons.close_rounded, size: 18, color: Colors.grey),
                onPressed: () {
                  _searchController.clear();
                  _onSearchChanged('');
                },
              )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (!_hasSearchedOnce) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_search_rounded, size: 70, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              "Andika jina la mtu unayemtafuta",
              style: TextStyle(color: Colors.grey.shade600, fontSize: 15, fontWeight: FontWeight.w300),
            ),
          ],
        ),
      );
    }

    if (_isSearching) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 70, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              "Hakuna mtumiaji aliyepatikana",
              style: TextStyle(color: Colors.grey.shade600, fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              "Jaribu jina lingine au hakikisha tahajia sahihi",
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13, fontWeight: FontWeight.w300),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _results.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final user = _results[index];
        final String imageUrl = (user.profileImageUrl != null && user.profileImageUrl!.isNotEmpty)
            ? user.profileImageUrl!
            : 'https://images.unsplash.com/photo-1633332755192-727a05c4013d?q=80&w=300';

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3)),
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            leading: CircleAvatar(radius: 26, backgroundImage: NetworkImage(imageUrl)),
            title: Text(
              "${user.name}, ${user.age}",
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            subtitle: (user.location != null && user.location!.isNotEmpty)
                ? Text(user.location!, style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5))
                : null,
            trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => PublicProfileScreen(uid: user.uid)),
              );
            },
          ),
        );
      },
    );
  }
}