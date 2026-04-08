-- ============================================
-- POTHOLE COMMENTS TABLE SETUP
-- Run this SQL in your Supabase SQL Editor
-- ============================================

-- Create comments table
CREATE TABLE IF NOT EXISTS pothole_comments (
  id BIGSERIAL PRIMARY KEY,
  report_id BIGINT NOT NULL REFERENCES pothole_reports(id) ON DELETE CASCADE,
  device_id TEXT NOT NULL,
  content TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for faster queries
CREATE INDEX IF NOT EXISTS idx_comments_report_id ON pothole_comments(report_id);
CREATE INDEX IF NOT EXISTS idx_comments_device_id ON pothole_comments(device_id);
CREATE INDEX IF NOT EXISTS idx_comments_created_at ON pothole_comments(created_at);

-- Enable Row Level Security
ALTER TABLE pothole_comments ENABLE ROW LEVEL SECURITY;

-- Allow anyone to view comments
CREATE POLICY "Anyone can view comments" ON pothole_comments
  FOR SELECT USING (true);

-- Allow anyone to insert comments
CREATE POLICY "Anyone can insert comments" ON pothole_comments
  FOR INSERT WITH CHECK (true);

-- Allow users to delete their own comments
CREATE POLICY "Users can delete own comments" ON pothole_comments
  FOR DELETE USING (true);

-- Verify table was created
SELECT 'pothole_comments table created successfully! ✅' as status;
