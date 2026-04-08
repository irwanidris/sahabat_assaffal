-- ============================================
-- PHASE 1: UPVOTE SYSTEM
-- Run this SQL in your Supabase SQL Editor
-- ============================================

-- Create the pothole_upvotes table
CREATE TABLE IF NOT EXISTS pothole_upvotes (
  id BIGSERIAL PRIMARY KEY,
  report_id BIGINT NOT NULL REFERENCES pothole_reports(id) ON DELETE CASCADE,
  device_id TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  -- Ensure one upvote per device per report
  UNIQUE(report_id, device_id)
);

-- Create index for faster lookups
CREATE INDEX IF NOT EXISTS idx_upvotes_report_id ON pothole_upvotes(report_id);
CREATE INDEX IF NOT EXISTS idx_upvotes_device_id ON pothole_upvotes(device_id);

-- Add upvote_count column to pothole_reports if it doesn't exist
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'pothole_reports' AND column_name = 'upvote_count'
  ) THEN
    ALTER TABLE pothole_reports ADD COLUMN upvote_count INTEGER DEFAULT 0;
  END IF;
END $$;

-- Add comment_count column if it doesn't exist
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'pothole_reports' AND column_name = 'comment_count'
  ) THEN
    ALTER TABLE pothole_reports ADD COLUMN comment_count INTEGER DEFAULT 0;
  END IF;
END $$;

-- Add share_count column if it doesn't exist
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'pothole_reports' AND column_name = 'share_count'
  ) THEN
    ALTER TABLE pothole_reports ADD COLUMN share_count INTEGER DEFAULT 0;
  END IF;
END $$;

-- Enable Row Level Security
ALTER TABLE pothole_upvotes ENABLE ROW LEVEL SECURITY;

-- Allow anyone to view upvotes
CREATE POLICY "Anyone can view upvotes" ON pothole_upvotes
  FOR SELECT USING (true);

-- Allow anyone to insert upvotes (based on device_id)
CREATE POLICY "Anyone can upvote" ON pothole_upvotes
  FOR INSERT WITH CHECK (true);

-- Allow users to remove their own upvotes
CREATE POLICY "Users can remove own upvotes" ON pothole_upvotes
  FOR DELETE USING (true);

-- Create spatial index for duplicate detection (if PostGIS is available)
-- CREATE INDEX IF NOT EXISTS idx_reports_location ON pothole_reports USING GIST (
--   ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)
-- );

-- ============================================
-- Verification: Check if everything was created
-- ============================================
SELECT 
  'pothole_upvotes table' as object,
  EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'pothole_upvotes') as exists;

SELECT 
  'upvote_count column' as object,
  EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'pothole_reports' AND column_name = 'upvote_count') as exists;
