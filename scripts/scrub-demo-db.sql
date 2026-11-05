SET FOREIGN_KEY_CHECKS = 0;
SET SQL_SAFE_UPDATES = 0;
SET SESSION sql_mode = REPLACE(REPLACE(@@sql_mode, 'STRICT_TRANS_TABLES', ''), 'STRICT_ALL_TABLES', '');

-- ===== credentials / tokens / logs: remove outright =====
TRUNCATE TABLE personal_access_tokens;
TRUNCATE TABLE audits;
TRUNCATE TABLE emergency_contact_phone_number;
TRUNCATE TABLE emergency_contact_team_member;
TRUNCATE TABLE emergency_contacts;
DELETE FROM sessions WHERE 1 = 1;

-- ===== users: every real person becomes a generic demo user; id 15 is the demo login =====
UPDATE users SET
  first_name = 'Demo',
  last_name  = CONCAT('User ', id),
  name       = CONCAT('Demo User ', id),
  email      = CONCAT('demo.user', id, '@example.com'),
  username   = CONCAT('demo', id),
  activation_key = NULL, remember_token = NULL, microsoft_token = NULL, microsoft_groups = NULL
WHERE email <> 'autodoc@stag.works' AND email <> 'khubaib@test.com';
UPDATE users SET first_name = 'Demo', last_name = 'Admin', name = 'Demo Admin' WHERE email = 'khubaib@test.com';

UPDATE team_members SET
  first_name = 'Team', last_name = CONCAT('Member ', id), nick_name = NULL, gender = NULL,
  personal_email = NULL, work_email = CONCAT('team', id, '@example.com'),
  hr_identifier = NULL, internal_extension = NULL,
  pet_names = NULL, interests = NULL, children_names = NULL, spouse_name = NULL, biography = NULL,
  birthdate = NULL, hired_on = '2020-01-01', termination = NULL, tax_type = NULL,
  gusto_contractor = NULL, gusto_employee = NULL, gusto = NULL, freshdesk_agent = NULL, freshdesk = NULL,
  harvest = NULL, zoom = NULL, lockdown_override_pin = NULL;

UPDATE users SET password = '!locked-until-demo-set-password';
UPDATE roles SET azure_role_id = NULL;

-- ===== CRM people and organisations =====
UPDATE contacts SET
  first_name = ELT(MOD(id, 20) + 1, 'Alex','Blake','Casey','Dana','Eli','Fran','Gale','Hollis','Indy','Jordan','Kai','Lee','Morgan','Noel','Oak','Parker','Quinn','Reese','Sky','Tate'),
  last_name  = ELT(MOD(id DIV 20, 20) + 1, 'Adams','Brooks','Carter','Dalton','Ellis','Foster','Grant','Hayes','Irwin','Jensen','Keller','Lowell','Mercer','Nolan','Owens','Porter','Quarry','Rowan','Stone','Turner'),
  username = CONCAT('contact', id),
  email = CONCAT('contact', id, '@example.com'),
  linked_in_url = NULL, twitter_handle = NULL, spouse_name = NULL, children_names = NULL,
  pet_names = NULL, interests = NULL, harvest = NULL, freshdesk = NULL,
  registration_date = NULL, work_anniversary = NULL, wedding_anniversary = NULL;
UPDATE contacts SET birth_month = NULL, birth_day = NULL;
UPDATE contacts SET title = ELT(MOD(id, 10) + 1, 'Operations Manager','Director','General Manager','IT Manager','Marketing Manager','Communications Lead','Member Services Rep','Billing Specialist','Engineer','Executive Assistant');

UPDATE clients SET
  name = CONCAT(
    ELT(MOD(id, 16) + 1, 'Northern','Riverbend','Summit','Lakeside','Prairie','Coastal','Highland','Valley','Cedar','Harbor','Granite','Meadow','Pioneer','Sunrise','Eastgate','Westfield'),
    ' ',
    ELT(MOD(id DIV 16, 8) + 1, 'Electric Cooperative','Municipal Utilities','Power Authority','Public Power District','Water District','Utility Board','Energy Services','Light & Power'),
    ' ', id),
  short_name = NULL, tax_id = NULL, quickbooks = NULL, harvest = NULL, freshdesk = NULL,
  client_assigned_vendor_id = NULL, override_payable_name = NULL, box = NULL, zoom_meeting_code = NULL;

UPDATE domains SET
  name = CONCAT('client-site-', id, '.example.com'),
  registrar_username = NULL, registrar_password = NULL, registrar_pin = NULL,
  registrar_notes = NULL, hosting_notes = NULL, deployment_path = NULL;

UPDATE addresses SET address1 = CONCAT(100 + id, ' Main Street'), address2 = NULL, validation_results = NULL;
UPDATE phone_numbers SET number = CONCAT('(555) 010-', LPAD(MOD(id, 10000), 4, '0'));

UPDATE brands SET
  name = CONCAT('Demo Brand ', id), legal_name = CONCAT('Demo Brand ', id, ' LLC'),
  website = 'https://example.com', email = CONCAT('brand', id, '@example.com'),
  billing_email_address = CONCAT('billing', id, '@example.com'), payable_to = CONCAT('Demo Brand ', id),
  online_payment_url = NULL, agreement_statement = NULL, invoice_disclaimer = NULL;

UPDATE competitors SET
  name = CONCAT('Competitor ', id), business_tagline = NULL, email = CONCAT('competitor', id, '@example.com'),
  website = 'https://example.com', pricing_strategy = NULL, tidbits = NULL, weaknesses = NULL,
  strengths = NULL, how_to_win = NULL, behavior = NULL, glassdoor_url = NULL;

UPDATE partners SET
  name = CONCAT('Partner ', id), website = 'https://example.com', email = CONCAT('partner', id, '@example.com');

-- ===== agreements and money: strip identifiers, perturb amounts by a per-row factor 0.6-1.4 =====
UPDATE agreements SET
  agreement_id = CONCAT('AG-', id), purchase_order = NULL, contracting_party = 'Demo Contracting Party', harvest = NULL,
  one_time_total = one_time_total * (0.6 + MOD(id * 37, 80) / 100),
  opt_in_total = opt_in_total * (0.6 + MOD(id * 37, 80) / 100),
  monthly_recurring_total = monthly_recurring_total * (0.6 + MOD(id * 37, 80) / 100),
  annual_recurring_total = annual_recurring_total * (0.6 + MOD(id * 37, 80) / 100);
UPDATE agreement_deliverables SET
  price = price * (0.6 + MOD(id * 53, 80) / 100),
  wholesale_price = wholesale_price * (0.6 + MOD(id * 53, 80) / 100);
UPDATE products SET
  list_price = list_price * (0.6 + MOD(id * 29, 80) / 100),
  list_price_profit = list_price_profit * (0.6 + MOD(id * 29, 80) / 100),
  landed_cost = landed_cost * (0.6 + MOD(id * 29, 80) / 100),
  wholesale_price = wholesale_price * (0.6 + MOD(id * 29, 80) / 100),
  wholesale_profit = wholesale_profit * (0.6 + MOD(id * 29, 80) / 100);
UPDATE salary_grades SET
  commission = commission * (0.6 + MOD(id * 41, 80) / 100),
  low = low * (0.6 + MOD(id * 41, 80) / 100),
  target = target * (0.6 + MOD(id * 41, 80) / 100),
  high = high * (0.6 + MOD(id * 41, 80) / 100);

-- ===== internal HR / infra / media content =====
UPDATE job_positions SET
  result_statement = 'Demo content', strategic_work = 'Demo content', tactical_work = 'Demo content',
  standards_work = 'Demo content', applicant_questions = 'Demo content', interview_questions = 'Demo content',
  position_overview = 'Demo content', expectations = 'Demo content', need_to_succeed = 'Demo content';
UPDATE infrastructures SET notes = NULL, ip = CONCAT('192.0.2.', MOD(id, 250) + 1);
UPDATE registrars SET notes = NULL;
UPDATE media SET
  name = CONCAT('media-', id, '.jpg'), url = CONCAT('https://example.com/media/', id), png_url = NULL,
  s3_path = CONCAT('demo/media-', id), png_s3_path = NULL, folder_path = 'demo', png_folder_path = NULL, etag = NULL;

SET FOREIGN_KEY_CHECKS = 1;
