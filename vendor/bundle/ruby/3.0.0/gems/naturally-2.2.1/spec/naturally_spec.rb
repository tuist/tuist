# coding: utf-8
require 'naturally'

describe Naturally do
  # Just a helper for these tests
  def it_sorts(opts = {})
    this = opts[:this]
    to_this = opts[:to_this]
    actual = Naturally.sort(this)
    expect(actual).to eq(to_this)
  end


  describe '#sort' do
    it 'supports a nicer by: syntax' do
      UbuntuVersion ||= Struct.new(:name, :version)
      releases = [
        UbuntuVersion.new('Saucy Salamander', '13.10'),
        UbuntuVersion.new('Raring Ringtail',  '13.04'),
        UbuntuVersion.new('Precise Pangolin', '12.04.4'),
        UbuntuVersion.new('Maverick Meerkat', '10.10'),
        UbuntuVersion.new('Quantal Quetzal',  '12.10'),
        UbuntuVersion.new('Lucid Lynx',       '10.04.4')
      ]

      actual = Naturally.sort releases, by: :version

      expect(actual.map(&:name)).to eq [
                                      'Lucid Lynx',
                                      'Maverick Meerkat',
                                      'Precise Pangolin',
                                      'Quantal Quetzal',
                                      'Raring Ringtail',
                                      'Saucy Salamander'
                                    ]
    end


    it 'sorts an array of strings nicely as if they were legal numbers' do
      it_sorts(
        this:    %w(676 676.1 676.11 676.12 676.2 676.3 676.9 676.10),
        to_this: %w(676 676.1 676.2 676.3 676.9 676.10 676.11 676.12)
      )
    end

    it 'sorts a more complex list of strings' do
      it_sorts(
        this:    %w(350 351 352 352.1 352.5 353.1 354 354.3 354.4 354.45 354.5),
        to_this: %w(350 351 352 352.1 352.5 353.1 354 354.3 354.4 354.5 354.45)
      )
    end

    it 'sorts when numbers have letters in them' do
      it_sorts(
        this:    %w(335 335.1 336a 336 337 337a 337.1 337.15 337.2),
        to_this: %w(335 335.1 336 336a 337 337.1 337.2 337.15 337a)
      )
    end

    it 'sorts when numbers have unicode letters in them' do
      it_sorts(
        this:    %w(335 335.1 336a 336 337 337я 337.1 337.15 337.2),
        to_this: %w(335 335.1 336 336a 337 337.1 337.2 337.15 337я)
      )
    end

    it 'sorts when letters have numbers in them' do
      it_sorts(
        this:    %w(PC1, PC3, PC5, PC7, PC9, PC10, PC11, PC12, PC13, PC14, PROF2, PBLI, SBP1, SBP3),
        to_this: %w(PBLI, PC1, PC3, PC5, PC7, PC9, PC10, PC11, PC12, PC13, PC14, PROF2, SBP1, SBP3)
      )
    end

    it 'sorts when letters have numbers and unicode characters in them' do
      it_sorts(
        this:    %w(АБ4, АБ2, АБ10, АБ12, АБ1, АБ3, АД8, АД5, АЩФ12, АЩФ8, ЫВА1),
        to_this: %w(АБ1, АБ2, АБ3, АБ4, АБ10, АБ12, АД5, АД8, АЩФ8, АЩФ12, ЫВА1)
      )
    end

    it 'sorts double digits with letters correctly' do
      it_sorts(
        this:    %w(12a 12b 12c 13a 13b 2 3 4 5 10 11 12),
        to_this: %w(2 3 4 5 10 11 12 12a 12b 12c 13a 13b)
      )
    end

    it 'sorts double digits with unicode letters correctly' do
      it_sorts(
        this:    %w(12а 12б 12в 13а 13б 2 3 4 5 10 11 12),
        to_this: %w(2 3 4 5 10 11 12 12а 12б 12в 13а 13б)
      )
    end

    it 'sorts strings suffixed with underscore and numbers correctly' do
      it_sorts(
        this:    %w(item_10 item_11 item_1 item_7 item_5 item_3 item_4 item_6 item_2),
        to_this: %w(item_1 item_2 item_3 item_4 item_5 item_6 item_7 item_10 item_11)
      )
    end

    it 'sorts letters with digits correctly' do
      it_sorts(
        this:    %w(1 a 2 b 3 c),
        to_this: %w(1 2 3 a b c)
      )
    end

    it 'sorts complex numbers with digits correctly' do
      it_sorts(
        this:    %w(1 a 2 b 3 c 1.1 a.1 1.2 a.2 1.3 a.3 b.1 ),
        to_this: %w(1 1.1 1.2 1.3 2 3 a a.1 a.2 a.3 b b.1 c)
      )
    end

    it 'sorts complex mixes of numbers and digits correctly' do
      it_sorts(
        this:    %w( 1.a.1 1.1 ),
        to_this: %w( 1.1 1.a.1 )
      )
    end

    it 'sorts complex mixes of numbers and digits correctly' do
      it_sorts(
        this:    %w( 1a1 1aa aaa ),
        to_this: %w( 1aa 1a1 aaa )
      )
    end
  end

  describe '#sort_naturally_by' do
    it 'sorts by an attribute' do
      UbuntuVersion ||= Struct.new(:name, :version)
      releases = [
        UbuntuVersion.new('Saucy Salamander', '13.10'),
        UbuntuVersion.new('Raring Ringtail',  '13.04'),
        UbuntuVersion.new('Precise Pangolin', '12.04.4'),
        UbuntuVersion.new('Maverick Meerkat', '10.10'),
        UbuntuVersion.new('Quantal Quetzal',  '12.10'),
        UbuntuVersion.new('Lucid Lynx',       '10.04.4')
      ]
      actual = Naturally.sort_by(releases, :version)
      expect(actual.map(&:name)).to eq [
        'Lucid Lynx',
        'Maverick Meerkat',
        'Precise Pangolin',
        'Quantal Quetzal',
        'Raring Ringtail',
        'Saucy Salamander'
      ]
    end

    it 'sorts by an attribute which contains unicode' do
      Thing = Struct.new(:number, :name)
      objects = [
        Thing.new('1.1', 'Москва'),
        Thing.new('1.2', 'Киев'),
        Thing.new('1.1.1', 'Париж'),
        Thing.new('1.1.2', 'Будапешт'),
        Thing.new('1.10', 'Брест'),
        Thing.new('2.1', 'Калуга'),
        Thing.new('1.3', 'Васюки')
      ]
      actual = objects.sort_by { |o| Naturally.normalize(o.name) }
      expect(actual.map(&:name)).to eq %w(
        Брест
        Будапешт
        Васюки
        Калуга
        Киев
        Москва
        Париж
      )
    end

    it 'sorts by an attribute which contains product names' do
      Product = Struct.new(:name)
      objects = [
          Product.new('2 awesome decks'),
          Product.new('Awesome deck')
      ]
      actual = Naturally.sort_by(objects, :name)
      expect(actual.map(&:name)).to eq [
        '2 awesome decks',
        'Awesome deck'
      ]
    end
  end

  describe '#sort_naturally_by_block' do
    it 'sorts using a block' do
      releases = [
        {:name => 'Saucy Salamander', :version => '13.10'},
        {:name => 'Raring Ringtail',  :version => '13.04'},
        {:name => 'Precise Pangolin', :version => '12.04.4'},
        {:name => 'Maverick Meerkat', :version => '10.10'},
        {:name => 'Quantal Quetzal',  :version => '12.10'},
        {:name => 'Lucid Lynx',       :version => '10.04.4'}
      ]
      actual = Naturally.sort_by(releases){|r| r[:version]}
      expect(actual.map{|r| r[:name]}).to eq [
        'Lucid Lynx',
        'Maverick Meerkat',
        'Precise Pangolin',
        'Quantal Quetzal',
        'Raring Ringtail',
        'Saucy Salamander'
      ]
    end
  end
end
