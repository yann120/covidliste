class User < ApplicationRecord
  include HasPhoneNumberConcern
  has_phone_number_types %i[mobile]
  rolify

  attr_accessor :address

  devise :magic_link_authenticatable, :confirmable, :validatable

  has_many :matches, dependent: :nullify
  has_many :messages, class_name: "Ahoy::Message", as: :user

  encrypts :firstname
  encrypts :lastname
  encrypts :phone_number
  encrypts :email

  blind_index :email

  validates :lat, presence: true, unless: proc { |u| u.persisted? }
  validates :lon, presence: true, unless: proc { |u| u.persisted? }
  validates :birthdate, presence: true
  validates :toc, presence: true, acceptance: true
  validates :statement, presence: true, acceptance: true, unless: proc { |u| u.reset_password_token.present? }
  validates :email,
    email: {
      mx: true,
      message: "Email invalide"
    },
    format: {
      without: /gmail\.fr|gamil\.com|gmil\.com|gmaul\.com|gamail\.com|gmai\.com|gmail\.cm|hormail\.com|hotmal\.com|hormail\.fr/i,
      message: "Email invalide"
    },
    if: :email_changed?

  before_save :randomize_lat_lon, if: -> { (saved_change_to_lat? || saved_change_to_lon?) }
  after_commit :reverse_geocode, if: -> { (saved_change_to_lat? || saved_change_to_lon?) && anonymized_at.nil? }

  scope :confirmed, -> { where.not(confirmed_at: nil) }
  scope :between_age, ->(min, max) { where("birthdate between ? and ?", max.years.ago, min.years.ago) }
  scope :with_roles, -> { joins(:roles) }

  PASSWORD_HINT = "#{Devise.password_length.min} caractères minimum. Idéalement plus long en mélangeant des minuscules, des majuscules et des chiffres."

  def randomize_lat_lon
    return if lat.nil? || lon.nil?
    results = ::RandomizeCoordinatesService.new(lat, lon).call
    self.lat = results[:lat]
    self.lon = results[:lon]
  end

  def ensure_lat_lon(address)
    return unless lat.nil? || lon.nil?
    results = GeocodingService.new(address).call
    self.lat = results[:lat]
    self.lon = results[:lon]
  end

  def reverse_geocode
    ReverseGeocodeResourceJob.perform_later(self)
  end

  def full_name
    if anonymized_at.nil?
      "#{firstname} #{lastname}"
    else
      "Anonymous"
    end
  end

  def to_s
    if anonymized_at.nil?
      if missing_identity?
        email
      else
        full_name
      end
    else
      "Anonymous"
    end
  end

  def age
    now = Time.now.utc.to_date
    now.year - birthdate.year - (now.month > birthdate.month || (now.month == birthdate.month && now.day >= birthdate.day) ? 0 : 1)
  end

  def confirmed?
    confirmed_at.present?
  end

  def missing_identity?
    firstname.blank? || lastname.blank?
  end

  def super_admin?
    has_role?(:super_admin)
  end

  def admin?
    has_role?(:admin) || super_admin?
  end

  def anonymize!
    return unless anonymized_at.nil?

    self.email = "anonymous#{id}+#{rand(100_000_000)}@null"
    self.firstname = nil
    self.lastname = nil
    self.address = nil
    self.lat = nil
    self.lon = nil
    self.zipcode = nil
    self.city = nil
    self.geo_citycode = nil
    self.geo_context = nil
    self.phone_number = nil
    self.birthdate = nil
    self.anonymized_at = Time.now.utc
    save(validate: false)
  end

  def to_csv
    columns = %w[created_at updated_at email firstname lastname birthdate phone_number address lat lon zipcode city geo_citycode geo_context]
    CSV.generate(headers: true) do |csv|
      csv << columns
      csv << columns.map { |column| public_send(column) }
    end
  end

  protected

  def skip_password_complexity?
    true unless encrypted_password_changed?
  end
end
