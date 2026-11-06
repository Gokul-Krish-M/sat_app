import 'package:flutter/material.dart';

import '../api/api_client.dart';

/// Network image from the API (photos are private, so the token is sent).
class AuthImage extends StatelessWidget {
  const AuthImage(this.api, this.path, {super.key, this.size, this.fit = BoxFit.cover});

  final ApiClient api;
  final String? path;
  final double? size;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      color: Colors.grey.shade300,
      child: Icon(Icons.person, size: (size ?? 48) * 0.6, color: Colors.grey.shade600),
    );
    if (path == null) return placeholder;
    return Image.network(
      api.imageUrl(path!),
      headers: api.authHeaders,
      width: size,
      height: size,
      fit: fit,
      errorBuilder: (_, _, _) => placeholder,
    );
  }
}

class Avatar extends StatelessWidget {
  const Avatar(this.api, this.path, {super.key, this.size = 48});
  final ApiClient api;
  final String? path;
  final double size;

  @override
  Widget build(BuildContext context) =>
      ClipOval(child: AuthImage(api, path, size: size));
}
