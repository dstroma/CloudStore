package CloudStore::Role::Driver;
use Role::Tiny;

requires qw(
  connect
  download
  upload
  find
  create_folder
  delete_folder
  delete_file
);
 
1;
