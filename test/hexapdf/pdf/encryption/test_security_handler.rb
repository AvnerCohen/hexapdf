# -*- encoding: utf-8 -*-

require 'test_helper'
require 'hexapdf/pdf/encryption/security_handler'
require 'hexapdf/pdf/document'
require 'hexapdf/pdf/stream'

describe HexaPDF::PDF::Encryption::SecurityHandler do

  class TestHandler < HexaPDF::PDF::Encryption::SecurityHandler

    attr_accessor :strf, :myopt
    public :dict

    def prepare_encrypt_dict(**options)
      dict[:Filter] = :test
      @key = "a" * key_length
      @strf ||= :aes
      @stmf ||= :arc4
      @eff ||= :identity
      [@key, @strf, @stmf, @eff]
    end

    def prepare_decryption(myopt: nil)
      @myopt = myopt
      @key = "a" * key_length
    end

  end


  before do
    @document = HexaPDF::PDF::Document.new
    @obj = @document.add({})
    @handler = TestHandler.new(@document)
  end

  it "doesn't have a valid encryption key directly after creation" do
    refute(@handler.encryption_key_valid?)
  end


  describe "set_up_encryption" do

    it "sets the trailer's /Encrypt entry to an encryption dictionary with a custom class" do
      @handler.set_up_encryption
      assert_kind_of(HexaPDF::PDF::Encryption::SecurityHandler::EncryptionDictionary,
                     @document.trailer[:Encrypt])
    end

    it "sets the correct /V value for the given key length and algorithm" do
      [[40, :arc4, 1], [128, :arc4, 2], [128, :arc4, 4],
       [128, :aes, 4], [256, :aes, 5]].each do |length, algorithm, version|
        @handler.set_up_encryption(key_length: length, algorithm: algorithm, force_V4: version == 4)
        assert_equal(version, @document.trailer[:Encrypt][:V])
      end
    end

    it "sets the correct /Length value for the given key length" do
      [[40, nil], [48, 48], [128, 128], [256, nil]].each do |key_length, result|
        algorithm = (key_length == 256 ? :aes : :arc4)
        @handler.set_up_encryption(key_length: key_length, algorithm: algorithm)
        assert_equal(result, @document.trailer[:Encrypt][:Length])
      end
    end

    it "calls the prepare_encrypt_dict method" do
      @handler.set_up_encryption
      assert_equal(:test, @document.trailer[:Encrypt][:Filter])
    end

    it "set's up the handler for encryption" do
      [:arc4, :aes].each do |algorithm|
        @handler.set_up_encryption(key_length: 128, algorithm: algorithm)
        @obj[:X] = @handler.encrypt_string('data', @obj)
        assert_equal('data', @handler.decrypt(@obj)[:X])
      end
    end

    it "generates a valid encryption key" do
      @handler.set_up_encryption
      assert(@handler.encryption_key_valid?)
    end

    it "fails for unsupported encryption key lengths" do
      exp = assert_raises(HexaPDF::UnsupportedEncryptionError) do
        @handler.set_up_encryption(key_length: 43)
      end
      assert_match(/Invalid key length/i, exp.message)
    end

    it "fails for unsupported encryption algorithms" do
      exp = assert_raises(HexaPDF::UnsupportedEncryptionError) do
        @handler.set_up_encryption(algorithm: :test)
      end
      assert_match(/Unsupported encryption algorithm/i, exp.message)
    end

    it "fails for the aes algorithm with key lengths != 128 or 256" do
      exp = assert_raises(HexaPDF::UnsupportedEncryptionError) do
        @handler.set_up_encryption(algorithm: :aes, key_length: 40)
      end
      assert_match(/AES algorithm.*key length/i, exp.message)
    end

    it "fails for the arc4 algorithm with a key length of 256" do
      exp = assert_raises(HexaPDF::UnsupportedEncryptionError) do
        @handler.set_up_encryption(algorithm: :arc4, key_length: 256)
      end
      assert_match(/ARC4 algorithm.*key length/i, exp.message)
    end

  end


  describe "set_up_decryption" do

    it "sets the handlers's dictionary to the encryption dictionary wrapped in a custom class" do
      @handler.set_up_decryption(Filter: :test, V: 1)
      assert_kind_of(HexaPDF::PDF::Encryption::SecurityHandler::EncryptionDictionary,
                     @handler.dict)
      assert_equal({Filter: :test, V: 1}, @handler.dict.value)
    end

    it "doesn't modify the trailer's /Encrypt dictionary" do
      @handler.set_up_decryption(Filter: :test, V: 4, Length: 128)
      assert_nil(@document.trailer[:Encrypt])
    end

    it "calls prepare_decryption" do
      @handler.set_up_decryption({Filter: :test, V: 4, Length: 128}, myopt: 5)
      assert_equal(5, @handler.myopt)
    end

    it "selects the correct algorithm based on the /V and /CF values" do
      @enc = @handler.dup

      [[:arc4, 40, {V: 1}],
       [:arc4, 80, {V: 2, Length: 80}],
       [:arc4, 128, {V: 4, StrF: :Mine, CF: {Mine: {CFM: :V2}}}],
       [:aes, 128, {V: 4, StrF: :Mine, CF: {Mine: {CFM: :AESV2}}}],
       [:aes, 256, {V: 5, StrF: :Mine, CF: {Mine: {CFM: :AESV3}}}],
       [:identity, 128, {V: 4, StrF: :Mine, CF: {Mine: {CFM: :None}}}],
       [:identity, 128, {V: 4, CF: {Mine: {CFM: :AESV2}}}],
      ].each do |alg, length, dict|
        @enc.strf = alg
        @enc.set_up_encryption(key_length: length, algorithm: (alg == :identity ? :aes : alg))
        @obj[:X] = @enc.encrypt_string('data', @obj)
        @handler.set_up_decryption(dict)
        assert_equal('data', @handler.decrypt(@obj)[:X])
      end
    end

    it "fails for unsupported /V values in the dict" do
      exp = assert_raises(HexaPDF::UnsupportedEncryptionError) do
        @handler.set_up_decryption(V: 3)
      end
      assert_match(/Unsupported encryption version/i, exp.message)
    end

    it "fails for unsupported crypt filter encryption methods" do
      exp = assert_raises(HexaPDF::UnsupportedEncryptionError) do
        @handler.set_up_decryption(V: 4, StrF: :Mine, CF: {Mine: {CFM: :Unknown}})
      end
      assert_match(/Unsupported encryption method/i, exp.message)
    end

  end


  describe "decrypt" do

    before do
      @handler.set_up_decryption(V: 1)
      @encrypted = @handler.encrypt_string('string', @obj)
      @obj.value = {Key: @encrypted.dup, Array: [@encrypted.dup], Hash: {Another: @encrypted.dup}}
    end

    it "decrypts all strings in an object" do
      @handler.decrypt(@obj)
      assert_equal('string', @obj[:Key])
      assert_equal('string', @obj[:Array][0])
      assert_equal('string', @obj[:Hash][:Another])
    end

    it "decrypts the content of a stream object" do
      data = HexaPDF::PDF::StreamData.new(Fiber.new { @encrypted })
      obj = @document.wrap({}, oid: @obj.oid, stream: data)
      @handler.decrypt(obj)
      assert_equal('string', obj.stream)
    end

    it "doesn't decrypt a document's Encrypt dictionary" do
      @document.trailer[:Encrypt] = @obj
      assert_equal(@encrypted, @handler.decrypt(@obj)[:Key])
    end

    it "doesn't decrypt XRef streams" do
      @obj[:Type] = :XRef
      assert_equal(@encrypted, @handler.decrypt(@obj)[:Key])
    end

    it "fails if V < 5 and the object number changes" do
      @obj.oid = 55
      @handler.decrypt(@obj)
      refute_equal('string', @obj[:Key])
    end
  end


  describe "encryption" do

    before do
      @handler.set_up_encryption(key_length: 128, algorithm: :arc4)
      @stream = @document.wrap({}, oid: 1, stream: HexaPDF::PDF::StreamData.new(Fiber.new { "string" }))
    end

    it "encrypts strings of indirect objects" do
      @obj[:Key] = @handler.encrypt_string('string', @obj)
      assert_equal('string', @handler.decrypt(@obj)[:Key])
    end

    it "encrypts streams" do
      result = TestHelper.collector(@handler.encrypt_stream(@stream))
      @stream.stream = HexaPDF::PDF::StreamData.new(Fiber.new { result })
      assert_equal('string', @handler.decrypt(@stream).stream)
    end

    it "doesn't encrypt strings in a document's Encrypt dictionary" do
      @document.trailer[:Encrypt][:Mine] = 'string'
      assert_equal('string', @handler.encrypt_string('string', @document.trailer[:Encrypt]))
    end

    it "doesn't encrypt XRef streams" do
      @stream[:Type] = :XRef
      assert_equal('string', @handler.encrypt_stream(@stream).resume)
    end

  end

end