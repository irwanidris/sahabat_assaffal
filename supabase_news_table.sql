-- ============================================
-- SAHABAT ASSAFFAL - NEWS TABLE SETUP
-- Run this SQL in your Supabase SQL Editor
-- ============================================

CREATE TABLE IF NOT EXISTS news (
  id BIGSERIAL PRIMARY KEY,
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  image_url TEXT,
  author TEXT NOT NULL,
  author_id UUID REFERENCES auth.users(id), -- Menambah kolum author_id
  category TEXT NOT NULL DEFAULT 'Berita Semasa',
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Function to handle updated_at
CREATE OR REPLACE FUNCTION handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ language 'plpgsql';

-- Trigger for updated_at
CREATE TRIGGER set_updated_at
BEFORE UPDATE ON news
FOR EACH ROW
EXECUTE PROCEDURE handle_updated_at();

-- Create indexes for faster queries
CREATE INDEX IF NOT EXISTS idx_news_status ON news(status);
CREATE INDEX IF NOT EXISTS idx_news_author ON news(author);
CREATE INDEX IF NOT EXISTS idx_news_category ON news(category);
CREATE INDEX IF NOT EXISTS idx_news_created_at ON news(created_at);

-- Enable Row Level Security
ALTER TABLE news ENABLE ROW LEVEL SECURITY;

-- Allow anyone to view approved news
CREATE POLICY "Anyone can view approved news" ON news
  FOR SELECT USING (status = 'approved');

-- Allow admins to view all news
-- Note: Replace 'is_admin' check with your actual admin logic if different
CREATE POLICY "Admins can view all news" ON news
  FOR SELECT USING (
    (auth.jwt() -> 'user_metadata' ->> 'is_admin')::boolean = true OR
    (auth.jwt() -> 'user_metadata' ->> 'is_admin_news')::boolean = true
  );

-- Allow news admins and super admins to insert news
CREATE POLICY "Admins can insert news" ON news
  FOR INSERT WITH CHECK (
    (auth.jwt() -> 'user_metadata' ->> 'is_admin')::boolean = true OR
    (auth.jwt() -> 'user_metadata' ->> 'is_admin_news')::boolean = true
  );

-- Allow news admins to update their own news and super admins to update any
CREATE POLICY "Admins can update news" ON news
  FOR UPDATE USING (
    (auth.jwt() -> 'user_metadata' ->> 'is_admin')::boolean = true OR
    (
      (auth.jwt() -> 'user_metadata' ->> 'is_admin_news')::boolean = true AND
      (auth.jwt() -> 'user_metadata' ->> 'full_name') = author
    )
  );

-- Allow admins to delete news
CREATE POLICY "Admins can delete news" ON news
  FOR DELETE USING (
    (auth.jwt() -> 'user_metadata' ->> 'is_admin')::boolean = true
  );
