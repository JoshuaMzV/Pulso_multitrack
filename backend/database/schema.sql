-- ============================================================================
-- PULSO CLOUD & ROLE-BASED ACCESS CONTROL (RBAC) SCHEMA
-- PostgreSQL / Supabase with Row Level Security (RLS)
-- ============================================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. Organizations (Bands, Churches, Ministries)
CREATE TABLE organizations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    slug TEXT UNIQUE NOT NULL,
    max_seats INT NOT NULL DEFAULT 5, -- Tier seat limit (e.g., 5 seats for Lite, 15 for Pro)
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. User Roles Enum
CREATE TYPE pulso_role AS ENUM ('leader', 'director', 'member_seat', 'guest');

-- 3. Organization Memberships (Seats)
CREATE TABLE organization_members (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    user_id UUID NOT NULL, -- References auth.users(id) in Supabase
    role pulso_role NOT NULL DEFAULT 'member_seat',
    instrument TEXT, -- E.g., 'Acoustic Guitar', 'Keys', 'Bass', 'Lead Vocals'
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    joined_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(organization_id, user_id)
);

-- Constraint Trigger: Guarantee organization does not exceed max_seats
CREATE OR REPLACE FUNCTION check_seat_limits()
RETURNS TRIGGER AS $$
DECLARE
    current_count INT;
    allowed_count INT;
BEGIN
    SELECT COUNT(*) INTO current_count 
    FROM organization_members 
    WHERE organization_id = NEW.organization_id AND is_active = TRUE;

    SELECT max_seats INTO allowed_count 
    FROM organizations 
    WHERE id = NEW.organization_id;

    IF current_count > allowed_count THEN
        RAISE EXCEPTION 'Seat limit exceeded for this organization (Max: %)', allowed_count;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER enforce_seat_limit
AFTER INSERT OR UPDATE ON organization_members
FOR EACH ROW EXECUTE FUNCTION check_seat_limits();

-- 4. Songs Library
CREATE TABLE songs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    artist TEXT,
    original_key TEXT NOT NULL DEFAULT 'C',
    bpm NUMERIC(5,2) NOT NULL DEFAULT 120.00,
    time_signature TEXT NOT NULL DEFAULT '4/4',
    sections_json JSONB DEFAULT '[]'::JSONB, -- Array of {name, bar, length}
    is_archived BOOLEAN NOT NULL DEFAULT FALSE,
    created_by UUID NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. Stems Storage (Audio Files metadata)
CREATE TABLE stems (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    song_id UUID NOT NULL REFERENCES songs(id) ON DELETE CASCADE,
    channel_index INT NOT NULL,
    name TEXT NOT NULL,          -- E.g., 'DRUMS', 'BASS', 'CLICK', 'GUIDE'
    stem_type TEXT NOT NULL,     -- 'click', 'guide', 'rhythm', 'melodic', 'pad'
    storage_path TEXT NOT NULL,  -- Path in Supabase S3 bucket
    default_gain NUMERIC(3,2) NOT NULL DEFAULT 0.80,
    default_pan NUMERIC(3,2) NOT NULL DEFAULT 0.00,
    default_bus INT NOT NULL DEFAULT 0, -- 0=Master, 1=Cue (Aux)
    peaks_url TEXT,              -- Cached precomputed waveform peaks
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. Setlists
CREATE TABLE setlists (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    event_date DATE NOT NULL,
    ambient_pad_key TEXT, -- Continuous pad between songs
    notes TEXT,
    created_by UUID NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 7. Setlist Items (Ordered songs with song-specific key & tempo overrides)
CREATE TABLE setlist_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    setlist_id UUID NOT NULL REFERENCES setlists(id) ON DELETE CASCADE,
    song_id UUID NOT NULL REFERENCES songs(id) ON DELETE CASCADE,
    position_order INT NOT NULL,
    target_key TEXT NOT NULL,       -- Band Leader's master key for the show
    target_bpm NUMERIC(5,2) NOT NULL,
    transition_type TEXT NOT NULL DEFAULT 'auto_pad', -- 'stop', 'crossfade', 'auto_pad'
    crossfade_duration NUMERIC(4,2) DEFAULT 3.00
);

-- 8. Member Personal Settings (Personal Transpose & Personal In-Ear Mix)
-- Allows a Member Seat to practice in a different key (e.g. Capo 2, Sax in Eb)
-- without altering the Band Leader's master stage setlist!
CREATE TABLE member_personal_setlist_preferences (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL,
    setlist_item_id UUID NOT NULL REFERENCES setlist_items(id) ON DELETE CASCADE,
    personal_key_offset INT NOT NULL DEFAULT 0, -- Semitones (-6 to +6)
    personal_fader_overrides JSONB DEFAULT '{}'::JSONB, -- { "stem_id": gain }
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, setlist_item_id)
);

-- ============================================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================================================
ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE songs ENABLE ROW LEVEL SECURITY;
ALTER TABLE stems ENABLE ROW LEVEL SECURITY;
ALTER TABLE setlists ENABLE ROW LEVEL SECURITY;
ALTER TABLE setlist_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE member_personal_setlist_preferences ENABLE ROW LEVEL SECURITY;

-- Helper functions to check roles
CREATE OR REPLACE FUNCTION is_org_leader(org_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM organization_members
        WHERE organization_id = org_id
          AND user_id = auth.uid()
          AND role IN ('leader', 'director')
          AND is_active = TRUE
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION is_org_member(org_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM organization_members
        WHERE organization_id = org_id
          AND user_id = auth.uid()
          AND is_active = TRUE
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Policies for Songs:
-- Everyone in the org can VIEW songs
CREATE POLICY "Org members can view songs"
ON songs FOR SELECT
USING (is_org_member(organization_id));

-- Only LEADERS can insert, update, or delete songs
CREATE POLICY "Only leaders can insert songs"
ON songs FOR INSERT
WITH CHECK (is_org_leader(organization_id));

CREATE POLICY "Only leaders can update songs"
ON songs FOR UPDATE
USING (is_org_leader(organization_id));

CREATE POLICY "Only leaders can delete songs"
ON songs FOR DELETE
USING (is_org_leader(organization_id));

-- Policies for Stems:
CREATE POLICY "Org members can view stems"
ON stems FOR SELECT
USING (EXISTS (
    SELECT 1 FROM songs WHERE songs.id = stems.song_id AND is_org_member(songs.organization_id)
));

CREATE POLICY "Only leaders can insert stems"
ON stems FOR INSERT
WITH CHECK (EXISTS (
    SELECT 1 FROM songs WHERE songs.id = stems.song_id AND is_org_leader(songs.organization_id)
));

-- Policies for Setlists:
CREATE POLICY "Org members can view setlists"
ON setlists FOR SELECT
USING (is_org_member(organization_id));

CREATE POLICY "Only leaders can manage setlists"
ON setlists FOR ALL
USING (is_org_leader(organization_id));

-- Policies for Personal Preferences:
-- Members can insert and update their OWN personal preferences
CREATE POLICY "Users can manage their own personal preferences"
ON member_personal_setlist_preferences FOR ALL
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());
