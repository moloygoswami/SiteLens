enum GalleryViewMode {
  grid2x2,
  grid3x3,
  list;

  int get crossAxisCount {
    switch (this) {
      case GalleryViewMode.grid2x2:
        return 2;
      case GalleryViewMode.grid3x3:
        return 3;
      case GalleryViewMode.list:
        return 1;
    }
  }
}
