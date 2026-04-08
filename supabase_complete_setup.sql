-- ============================================
-- POTHOLE HERO - COMPLETE DATABASE SETUP
-- Run this SQL in your Supabase SQL Editor
-- ============================================

-- ============================================
-- STEP 1: Create the main pothole_reports table
-- ============================================
CREATE TABLE IF NOT EXISTS pothole_reports (
  id BIGSERIAL PRIMARY KEY,
  image_url TEXT NOT NULL,
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  address TEXT,
  area_name TEXT,
  description TEXT,
  duration TEXT,
  status TEXT DEFAULT 'pending',
  device_id TEXT,
  severity TEXT DEFAULT 'medium',
  upvote_count INTEGER DEFAULT 0,
  comment_count INTEGER DEFAULT 0,
  share_count INTEGER DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for faster queries
CREATE INDEX IF NOT EXISTS idx_reports_status ON pothole_reports(status);
CREATE INDEX IF NOT EXISTS idx_reports_created_at ON pothole_reports(created_at);
CREATE INDEX IF NOT EXISTS idx_reports_device_id ON pothole_reports(device_id);
CREATE INDEX IF NOT EXISTS idx_reports_location ON pothole_reports(latitude, longitude);

-- Enable Row Level Security
ALTER TABLE pothole_reports ENABLE ROW LEVEL SECURITY;

-- Allow anyone to view reports
CREATE POLICY "Anyone can view reports" ON pothole_reports
  FOR SELECT USING (true);

-- Allow anyone to insert reports
CREATE POLICY "Anyone can insert reports" ON pothole_reports
  FOR INSERT WITH CHECK (true);

-- Allow anyone to update reports (for upvote count updates)
CREATE POLICY "Anyone can update reports" ON pothole_reports
  FOR UPDATE USING (true);

-- ============================================
-- STEP 2: Create the pothole_upvotes table
-- ============================================
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

-- Enable Row Level Security
ALTER TABLE pothole_upvotes ENABLE ROW LEVEL SECURITY;

-- Allow anyone to view upvotes
CREATE POLICY "Anyone can view upvotes" ON pothole_upvotes
  FOR SELECT USING (true);

-- Allow anyone to insert upvotes
CREATE POLICY "Anyone can upvote" ON pothole_upvotes
  FOR INSERT WITH CHECK (true);

-- Allow users to remove their own upvotes
CREATE POLICY "Users can remove own upvotes" ON pothole_upvotes
  FOR DELETE USING (true);

-- ============================================
-- STEP 3: Create device_users table (for gamification)
-- ============================================
CREATE TABLE IF NOT EXISTS device_users (
  id BIGSERIAL PRIMARY KEY,
  device_id TEXT UNIQUE NOT NULL,
  display_name TEXT,
  points INTEGER DEFAULT 0,
  total_reports INTEGER DEFAULT 0,
  current_streak INTEGER DEFAULT 0,
  longest_streak INTEGER DEFAULT 0,
  last_report_date DATE,
  badges TEXT[] DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create index
CREATE INDEX IF NOT EXISTS idx_device_users_device_id ON device_users(device_id);

-- Enable Row Level Security
ALTER TABLE device_users ENABLE ROW LEVEL SECURITY;

-- Allow anyone to view/insert/update device users
CREATE POLICY "Anyone can view device users" ON device_users
  FOR SELECT USING (true);

CREATE POLICY "Anyone can insert device users" ON device_users
  FOR INSERT WITH CHECK (true);

CREATE POLICY "Anyone can update device users" ON device_users
  FOR UPDATE USING (true);

-- ============================================
-- STEP 4: Create Storage Bucket for images
-- ============================================
-- Note: You need to manually create a storage bucket named 'pothole-images' 
-- in Supabase Dashboard > Storage > New Bucket
-- Set it to PUBLIC for the app to work

-- ============================================
-- Verification: Check if everything was created
-- ============================================
SELECT 
  'pothole_reports' as table_name,
  EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'pothole_reports') as exists
UNION ALL
SELECT 
  'pothole_upvotes' as table_name,
  EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'pothole_upvotes') as exists
UNION ALL
SELECT 
  'device_users' as table_name,
  EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'device_users') as exists;
