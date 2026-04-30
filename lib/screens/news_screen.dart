import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/supabase_service.dart';

class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> with SingleTickerProviderStateMixin {
  late final WebViewController _fbController;
  final SupabaseService _supabaseService = SupabaseService();
  bool _isLoadingFB = true;
  late TabController _tabController;
  List<Map<String, dynamic>> _nativeNews = [];
  bool _isLoadingNative = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    
    // Initialize FB WebView
    _fbController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _isLoadingFB = true),
          onPageFinished: (_) => setState(() => _isLoadingFB = false),
        ),
      )
      ..loadRequest(Uri.parse('https://www.facebook.com/plugins/page.php?href=https%3A%2F%2Fwww.facebook.com%2Fassaffal.lahaddatu&tabs=timeline&width=500&height=1000&small_header=true&adapt_container_width=true&hide_cover=false&show_facepile=false'));

    _fetchNativeNews();
  }

  Future<void> _fetchNativeNews() async {
    setState(() => _isLoadingNative = true);
    final news = await _supabaseService.fetchNews(approvedOnly: true);
    if (mounted) {
      setState(() {
        _nativeNews = news;
        _isLoadingNative = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 110,
          bottom: 100,
        ),
        child: Column(
          children: [
            _buildTabBar(isDarkMode),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildNativeNewsList(isDarkMode),
                  _buildFBWebView(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar(bool isDarkMode) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: AppTheme.primaryRed,
        ),
        labelColor: Colors.white,
        unselectedLabelColor: isDarkMode ? Colors.white70 : Colors.black54,
        tabs: const [
          Tab(text: 'BERITA UTAMA'),
          Tab(text: 'FB ASSAFFAL'),
        ],
      ),
    );
  }

  Widget _buildNativeNewsList(bool isDarkMode) {
    if (_isLoadingNative) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primaryRed));
    }

    if (_nativeNews.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.newspaper, size: 64, color: (isDarkMode ? Colors.white24 : Colors.black12)),
            const SizedBox(height: 16),
            const Text('Tiada berita buat masa ini.'),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchNativeNews,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _nativeNews.length,
        itemBuilder: (context, index) {
          final news = _nativeNews[index];
          return NewsCard(news: news, isDarkMode: isDarkMode, onTap: () => _showNewsDetail(news));
        },
      ),
    );
  }
}

class NewsCard extends StatefulWidget {
  final Map<String, dynamic> news;
  final bool isDarkMode;
  final VoidCallback onTap;

  const NewsCard({
    super.key,
    required this.news,
    required this.isDarkMode,
    required this.onTap,
  });

  @override
  State<NewsCard> createState() => _NewsCardState();
}

class _NewsCardState extends State<NewsCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final news = widget.news;
    final isDarkMode = widget.isDarkMode;
    final String title = news['title'] ?? 'Tiada Tajuk';
    final String content = news['content'] ?? '';
    final String? imageUrl = news['image_url'];
    final String category = news['category'] ?? 'Berita';
    final DateTime createdAt = DateTime.parse(news['created_at'] ?? DateTime.now().toIso8601String());
    final String formattedDate = DateFormat('dd MMM yyyy').format(createdAt);
    final String formattedTime = DateFormat('hh:mm a').format(createdAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: isDarkMode ? AppTheme.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDarkMode ? 0.3 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imageUrl != null && imageUrl.isNotEmpty)
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    child: Image.network(
                      imageUrl,
                      height: 220,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        height: 150,
                        color: Colors.grey[200],
                        child: const Icon(Icons.broken_image, color: Colors.grey),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.3),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryRed,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          category.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(Icons.access_time_rounded, 
                        size: 14, 
                        color: isDarkMode ? Colors.white38 : Colors.black38
                      ),
                      const SizedBox(width: 4),
                      Text(
                        "$formattedDate • $formattedTime",
                        style: TextStyle(
                          fontSize: 11, 
                          fontWeight: FontWeight.w500,
                          color: isDarkMode ? Colors.white38 : Colors.black38
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                      color: isDarkMode ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Kandungan Berita
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        content,
                        maxLines: _isExpanded ? null : 3,
                        overflow: _isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.6,
                          color: isDarkMode ? Colors.white70 : Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: () {
                          setState(() {
                            _isExpanded = !_isExpanded;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppTheme.primaryRed.withOpacity(0.5)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _isExpanded ? 'TUTUP' : 'BACA LAGI',
                            style: const TextStyle(
                              color: AppTheme.primaryRed,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Info Author & Footer
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Oleh: ${news['author'] ?? 'Admin'}',
                        style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: isDarkMode ? Colors.white38 : Colors.black45,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension on _NewsScreenState {

  void _showNewsDetail(Map<String, dynamic> news) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.6,
        maxChildSize: 0.97,
        builder: (_, scrollController) => Container(
          decoration: BoxDecoration(
            color: isDarkMode ? AppTheme.darkBackground : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDarkMode ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                  children: [
                    if (news['image_url'] != null)
                      Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Image.network(
                              news['image_url'],
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryRed.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          (news['category'] ?? 'Umum').toUpperCase(),
                          style: const TextStyle(
                            color: AppTheme.primaryRed,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      news['title'] ?? '',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        height: 1.2,
                        color: isDarkMode ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: AppTheme.primaryRed.withOpacity(0.1),
                          child: const Icon(Icons.person, size: 18, color: AppTheme.primaryRed),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              news['author'] ?? 'Admin',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: isDarkMode ? Colors.white : Colors.black87,
                              ),
                            ),
                            Text(
                              DateFormat('dd MMMM yyyy, hh:mm a').format(DateTime.parse(news['created_at'])),
                              style: TextStyle(
                                color: isDarkMode ? Colors.white38 : Colors.black38,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Divider(),
                    ),
                    Text(
                      news['content'] ?? '',
                      style: TextStyle(
                        fontSize: 17,
                        height: 1.8,
                        letterSpacing: 0.2,
                        color: isDarkMode ? Colors.white.withOpacity(0.9) : Colors.black87.withOpacity(0.8),
                      ),
                    ),
                    const SizedBox(height: 60),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFBWebView() {
    return Stack(
      children: [
        WebViewWidget(controller: _fbController),
        if (_isLoadingFB)
          const Center(child: CircularProgressIndicator(color: AppTheme.primaryRed)),
      ],
    );
  }
}
