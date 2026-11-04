import 'package:flutter/material.dart';

const _dir = 'assets/icons';

/// One registry for every icon in the app. Entries with an [asset] use the
/// stroke icon set drawn on the design canvas (24 px, recoloured at runtime);
/// the rest fall back to Material icons.
enum AppIcons {
  home(Icons.home_rounded, asset: '$_dir/home.svg'),
  settings(Icons.settings_rounded, asset: '$_dir/sliders.svg'),
  camera(Icons.photo_camera_rounded, asset: '$_dir/camera.svg'),
  flashOn(Icons.flash_on_rounded, asset: '$_dir/bolt.svg'),
  flashOff(Icons.flash_off_rounded, asset: '$_dir/bolt_off.svg'),
  gallery(Icons.photo_library_rounded, asset: '$_dir/gallery.svg'),
  files(Icons.folder_rounded, asset: '$_dir/files.svg'),
  single(Icons.crop_portrait_rounded),
  batch(Icons.auto_awesome_motion_rounded),
  document(Icons.description_rounded, asset: '$_dir/document.svg'),
  idCard(Icons.badge_rounded, asset: '$_dir/id_card.svg'),
  passport(Icons.menu_book_rounded, asset: '$_dir/passport.svg'),
  back(Icons.arrow_back_rounded, asset: '$_dir/back.svg'),
  close(Icons.close_rounded, asset: '$_dir/close.svg'),
  more(Icons.more_vert_rounded, asset: '$_dir/more.svg'),
  check(Icons.check_rounded, asset: '$_dir/check.svg'),
  search(Icons.search_rounded, asset: '$_dir/search.svg'),
  edit(Icons.tune_rounded, asset: '$_dir/sliders.svg'),
  text(Icons.text_fields_rounded, asset: '$_dir/text.svg'),
  print(Icons.print_rounded, asset: '$_dir/print.svg'),
  share(Icons.ios_share_rounded, asset: '$_dir/share.svg'),
  save(Icons.save_alt_rounded, asset: '$_dir/save.svg'),
  rename(Icons.drive_file_rename_outline_rounded, asset: '$_dir/pencil.svg'),
  reorder(Icons.swap_vert_rounded, asset: '$_dir/reorder.svg'),
  addPage(Icons.add_photo_alternate_rounded, asset: '$_dir/plus.svg'),
  delete(Icons.delete_outline_rounded, asset: '$_dir/delete.svg'),
  rotateLeft(Icons.rotate_left_rounded, asset: '$_dir/rotate_left.svg'),
  rotateRight(Icons.rotate_right_rounded, asset: '$_dir/rotate_right.svg'),
  autoEdges(Icons.crop_free_rounded, asset: '$_dir/auto_edges.svg'),
  retake(Icons.replay_rounded, asset: '$_dir/camera.svg'),
  compare(Icons.compare_rounded, asset: '$_dir/compare.svg'),
  reset(Icons.restart_alt_rounded),
  copy(Icons.copy_rounded, asset: '$_dir/copy.svg'),
  cut(Icons.content_cut_rounded, asset: '$_dir/cut.svg'),
  selectAll(Icons.select_all_rounded),
  video(Icons.play_circle_fill_rounded, asset: '$_dir/video.svg'),
  play(Icons.play_arrow_rounded, asset: '$_dir/play.svg'),
  lock(Icons.lock_rounded),
  theme(Icons.brightness_6_rounded),
  storage(Icons.storage_rounded),
  privacy(Icons.privacy_tip_rounded),
  faq(Icons.help_outline_rounded),
  star(Icons.star_rounded),
  pdf(Icons.picture_as_pdf_rounded),
  image(Icons.image_rounded, asset: '$_dir/gallery.svg'),
  info(Icons.info_outline_rounded, asset: '$_dir/info.svg'),
  warning(Icons.error_outline_rounded, asset: '$_dir/warning.svg'),
  online(Icons.wifi_rounded, asset: '$_dir/wifi.svg'),
  offline(Icons.wifi_off_rounded, asset: '$_dir/wifi_off.svg'),
  chevronRight(Icons.chevron_right_rounded, asset: '$_dir/chevron_right.svg'),
  chevronDown(Icons.expand_more_rounded, asset: '$_dir/chevron_down.svg'),
  clock(Icons.schedule_rounded, asset: '$_dir/clock.svg'),
  bolt(Icons.bolt_rounded, asset: '$_dir/bolt.svg'),
  dragHandle(Icons.drag_handle_rounded),
  pages(Icons.filter_none_rounded, asset: '$_dir/pages.svg');

  const AppIcons(this.fallback, {this.asset});

  final IconData fallback;
  final String? asset;
}
