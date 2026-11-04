import 'package:flutter/material.dart';

/// One registry for every icon in the app. Each entry has a Material fallback
/// and an optional SVG asset path; when the 24 px SVG set from the design
/// canvas lands in `assets/icons/`, set `asset` here and nothing else changes.
enum AppIcons {
  home(Icons.home_rounded),
  settings(Icons.settings_rounded),
  camera(Icons.photo_camera_rounded),
  flashOn(Icons.flash_on_rounded),
  flashOff(Icons.flash_off_rounded),
  gallery(Icons.photo_library_rounded),
  files(Icons.folder_rounded),
  single(Icons.crop_portrait_rounded),
  batch(Icons.auto_awesome_motion_rounded),
  idCard(Icons.badge_rounded),
  passport(Icons.menu_book_rounded),
  back(Icons.arrow_back_rounded),
  close(Icons.close_rounded),
  more(Icons.more_vert_rounded),
  check(Icons.check_rounded),
  search(Icons.search_rounded),
  edit(Icons.tune_rounded),
  text(Icons.text_fields_rounded),
  print(Icons.print_rounded),
  share(Icons.ios_share_rounded),
  save(Icons.save_alt_rounded),
  rename(Icons.drive_file_rename_outline_rounded),
  reorder(Icons.swap_vert_rounded),
  addPage(Icons.add_photo_alternate_rounded),
  delete(Icons.delete_outline_rounded),
  rotateLeft(Icons.rotate_left_rounded),
  rotateRight(Icons.rotate_right_rounded),
  autoEdges(Icons.crop_free_rounded),
  retake(Icons.replay_rounded),
  compare(Icons.compare_rounded),
  reset(Icons.restart_alt_rounded),
  copy(Icons.copy_rounded),
  cut(Icons.content_cut_rounded),
  selectAll(Icons.select_all_rounded),
  video(Icons.play_circle_fill_rounded),
  lock(Icons.lock_rounded),
  theme(Icons.brightness_6_rounded),
  storage(Icons.storage_rounded),
  privacy(Icons.privacy_tip_rounded),
  faq(Icons.help_outline_rounded),
  star(Icons.star_rounded),
  pdf(Icons.picture_as_pdf_rounded),
  image(Icons.image_rounded),
  info(Icons.info_outline_rounded),
  warning(Icons.error_outline_rounded),
  offline(Icons.wifi_off_rounded),
  chevronRight(Icons.chevron_right_rounded),
  document(Icons.description_rounded),
  bolt(Icons.bolt_rounded),
  dragHandle(Icons.drag_handle_rounded),
  pages(Icons.filter_none_rounded);

  // ignore: unused_element_parameter
  const AppIcons(this.fallback, {this.asset});

  final IconData fallback;
  final String? asset;
}
