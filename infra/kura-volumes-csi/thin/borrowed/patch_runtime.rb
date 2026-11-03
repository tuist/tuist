#!/usr/bin/env ruby
# Applies ONLY to a disposable checkout used to build the prototype artifact.
require 'fileutils'
abort 'explicit experimental build opt-in required' unless ENV['KURA_BORROWED_BUILD'] == '1'
root = File.expand_path(ARGV.fetch(0))
path = File.join(root, 'src/store.rs')
s = File.read(path)
def replace_once(s, from, to)
  raise "runtime source drift: #{from[0,100]}" unless s.scan(from).size == 1
  s.sub(from, to)
end
s = replace_once(s, 'let segment = SegmentReference::new(Uuid::now_v7().to_string(), now_ms());',
  'let segment = SegmentReference::new(borrowed_prototype::new_id(&self.data_dir)?, now_ms());')
s = replace_once(s, '        if needs_new_segment {', <<~'RS'.rstrip)
        let needs_new_segment = needs_new_segment || borrowed_prototype::must_rotate(
            &self.data_dir, snapshot.state.active().map(|s| s.segment_id.as_str()))?;
        if needs_new_segment {
RS
s = replace_once(s, '        available_disk_bytes(&self.data_dir)',
  '        borrowed_prototype::available(&self.data_dir)')
s = replace_once(s, '        segment_path(&self.data_dir, segment_id)',
  '        borrowed_prototype::path(&self.data_dir, segment_id)')
s = replace_once(s, '            let requested = self.disk_pressure_requested.load(Ordering::Acquire);', <<~'RS'.rstrip)
            if let Err(error) = self.prototype_reclaim_unit().await {
                tracing::warn!(error, "borrowed prototype drain blocked");
            }
            let requested = self.disk_pressure_requested.load(Ordering::Acquire);
RS
# Keep the existing orphan cleanup and apply it to every mounted unit. Missing
# referenced units are rejected before recovery, not treated as empty storage.
s = replace_once(s, '        let segments_dir = self.data_dir.join("segments");', <<~'RS'.rstrip)
        self.prototype_verify_units()?;
        let mut total_swept = 0;
        for segments_dir in borrowed_prototype::directories(&self.data_dir)? {
RS
s = replace_once(s, 'Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(0),',
  'Err(error) if error.kind() == std::io::ErrorKind::NotFound => continue,')
s = replace_once(s, "        Ok(swept)\n    }\n\n    fn segment_path", "        total_swept += swept;\n        }\n        Ok(total_swept)\n    }\n\n    fn segment_path")
s << "\n#[path = \"borrowed_prototype.rs\"]\nmod borrowed_prototype;\n"
File.write(path, s)
FileUtils.cp(File.join(__dir__, 'runtime.rs.fixture'), File.join(root, 'src/borrowed_prototype.rs'))
app_path = File.join(root, 'src/app.rs')
app = File.read(app_path)
app = replace_once(app, '        vec![config.tmp_dir.clone(), config.data_dir.clone()],', <<~'RS'.rstrip)
        {
            let mut roots = vec![config.tmp_dir.clone(), config.data_dir.clone()];
            if let Some(root) = std::env::var_os("KURA_BORROWED_PROTOTYPE") {
                roots.push(std::path::PathBuf::from(root).join("units"));
            }
            roots
        },
RS
File.write(app_path, app)
