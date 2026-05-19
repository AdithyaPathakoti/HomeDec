import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image_picker/image_picker.dart';
import 'processing_screen.dart';

class FabricDesign {
  final String title;
  final String prompt;
  final String imagePath;
  final String description;

  FabricDesign({
    required this.title,
    required this.prompt,
    required this.imagePath,
    required this.description,
  });
}

class CatalogScreen extends StatefulWidget {
  final Uint8List originalImageBytes;
  final Uint8List maskImageBytes;

  const CatalogScreen({
    Key? key,
    required this.originalImageBytes,
    required this.maskImageBytes,
  }) : super(key: key);

  @override
  _CatalogScreenState createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final List<FabricDesign> designs = [
    FabricDesign(
        title: "Classic Beige Floral", 
        prompt: "Beige fabric with vertical stripes and small blue floral patterns, realistic folds, high quality textile", 
        imagePath: "assets/design1.jpg",
        description: "Elegant beige linen featuring soft blue florals and classic stripes."),
    FabricDesign(
        title: "Luxury Rose Pattern", 
        prompt: "Luxury modern floral bedsheet fabric with realistic folds and shadows", 
        imagePath: "",
        description: "AI-generated rich crimson rose pattern for a romantic, luxurious bedroom feel."),
    FabricDesign(
        title: "Minimalist Beige", 
        prompt: "Minimalist soft beige linen fabric texture, realistic lighting", 
        imagePath: "",
        description: "A clean, modern, organic beige fabric texture with subtle lighting."),
    FabricDesign(
        title: "Velvet Emerald", 
        prompt: "Rich emerald green velvet fabric texture, realistic folds, high quality", 
        imagePath: "",
        description: "Plush, deep emerald green velvet that catches shadows beautifully."),
  ];

  bool _isAssetLoading = false;
  String? _loadingTitle;

  Future<void> _handleCustomDesignUpload(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProcessingScreen(
                originalImageBytes: widget.originalImageBytes,
                maskImageBytes: widget.maskImageBytes,
                prompt: "Custom fabric pattern design",
                designBytes: bytes,
              ),
            ),
          );
        }
      }
    } catch (e) {
      print("Error picking custom design image: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load selected custom design pattern: $e')),
      );
    }
  }

  void _showImageSourceSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[950],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Upload Custom Fabric Pattern',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              'Take a photo of a real fabric, or select a downloaded pattern to wrap onto your furniture.',
              style: TextStyle(color: Colors.grey[400], fontSize: 13),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _handleCustomDesignUpload(ImageSource.camera);
              },
              icon: Icon(Icons.camera_alt, color: Colors.black),
              label: Text('Take a Photo'),
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _handleCustomDesignUpload(ImageSource.gallery);
              },
              icon: Icon(Icons.photo_library, color: Colors.white),
              label: Text('Choose from Gallery'),
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 16),
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white24),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectDesign(FabricDesign design) async {
    if (design.imagePath.isNotEmpty) {
      // Local asset - load its bytes to send to the backend
      setState(() {
        _isAssetLoading = true;
        _loadingTitle = design.title;
      });

      try {
        final ByteData assetData = await rootBundle.load(design.imagePath);
        final Uint8List designBytes = assetData.buffer.asUint8List();
        
        setState(() {
          _isAssetLoading = false;
          _loadingTitle = null;
        });

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProcessingScreen(
              originalImageBytes: widget.originalImageBytes,
              maskImageBytes: widget.maskImageBytes,
              prompt: design.prompt,
              designBytes: designBytes,
            ),
          ),
        );
      } catch (e) {
        setState(() {
          _isAssetLoading = false;
          _loadingTitle = null;
        });
        print("Error loading asset design bytes: $e");
        // Fallback to text prompt only if asset fails to load
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProcessingScreen(
              originalImageBytes: widget.originalImageBytes,
              maskImageBytes: widget.maskImageBytes,
              prompt: design.prompt,
            ),
          ),
        );
      }
    } else {
      // Cloud prompt only
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ProcessingScreen(
            originalImageBytes: widget.originalImageBytes,
            maskImageBytes: widget.maskImageBytes,
            prompt: design.prompt,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('Choose Fabric Style', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          // Subtle elegant background gradient
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black,
                    const Color(0xFF0A0A0A),
                    Colors.grey[900]!,
                  ],
                ),
              ),
            ),
          ),
          
          SafeArea(
            child: CustomScrollView(
              physics: BouncingScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      Text(
                        "Fabric Showroom",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        "Pick a state-of-the-art fabric template, or upload a custom texture from your phone to overlay on the bedsheet instantly.",
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                      SizedBox(height: 24),
                    ]),
                  ),
                ),
                
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 0.78,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        // The very first card is our high-end Custom Pattern upload card
                        if (index == 0) {
                          return _buildCustomUploadCard();
                        }
                        
                        // Remaining cards are the curated templates
                        final design = designs[index - 1];
                        return _buildFabricTemplateCard(design);
                      },
                      childCount: designs.length + 1,
                    ),
                  ),
                ),
                
                SliverPadding(padding: EdgeInsets.only(bottom: 32)),
              ],
            ),
          ),
          
          // Full-screen blocker while loading local assets
          if (_isAssetLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.7),
                child: Center(
                  child: Card(
                    color: Colors.grey[900],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 16),
                          Text(
                            "Loading ${_loadingTitle ?? 'Fabric'}...",
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 4),
                          Text(
                            "Preparing high-res texture bytes",
                            style: TextStyle(color: Colors.grey[400], fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCustomUploadCard() {
    return GestureDetector(
      onTap: _showImageSourceSelector,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.purple[900]!,
              Colors.blue[900]!,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.purple.withOpacity(0.3),
              blurRadius: 15,
              offset: Offset(0, 5),
            ),
          ],
          border: Border.all(color: Colors.white30, width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white30),
              ),
              child: Icon(
                Icons.add_photo_alternate,
                size: 40,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 16),
            Text(
              "Upload Pattern",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 16,
                letterSpacing: 0.2,
              ),
            ),
            SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                "Use camera photo or a custom image",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFabricTemplateCard(FabricDesign design) {
    final bool hasImage = design.imagePath.isNotEmpty;
    
    return GestureDetector(
      onTap: () => _selectDesign(design),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0A0A0A).withOpacity(0.8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 5,
              child: ClipRRect(
                borderRadius: BorderRadius.vertical(top: Radius.circular(19)),
                child: hasImage
                    ? Image.asset(
                        design.imagePath,
                        fit: BoxFit.cover,
                        width: double.infinity,
                      )
                    : Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.grey[900]!,
                              const Color(0xFF0A0A0A),
                            ],
                          ),
                        ),
                        child: Center(
                          child: Container(
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.auto_awesome,
                              size: 32,
                              color: Colors.white38,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            design.title,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!hasImage)
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.blue.withOpacity(0.3)),
                            ),
                            child: Text(
                              "AI",
                              style: TextStyle(color: Colors.blue[300], fontSize: 8, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: 4),
                    Text(
                      design.description,
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 10,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
