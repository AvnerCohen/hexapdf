# -*- encoding: utf-8 -*-
#
#--
# This file is part of HexaPDF.
#
# HexaPDF - A Versatile PDF Creation and Manipulation Library For Ruby
# Copyright (C) 2016 Thomas Leitner
#
# HexaPDF is free software: you can redistribute it and/or modify it
# under the terms of the GNU Affero General Public License version 3 as
# published by the Free Software Foundation with the addition of the
# following permission added to Section 15 as permitted in Section 7(a):
# FOR ANY PART OF THE COVERED WORK IN WHICH THE COPYRIGHT IS OWNED BY
# THOMAS LEITNER, THOMAS LEITNER DISCLAIMS THE WARRANTY OF NON
# INFRINGEMENT OF THIRD PARTY RIGHTS.
#
# HexaPDF is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public
# License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with HexaPDF. If not, see <http://www.gnu.org/licenses/>.
#
# The interactive user interfaces in modified source and object code
# versions of HexaPDF must display Appropriate Legal Notices, as required
# under Section 5 of the GNU Affero General Public License version 3.
#
# In accordance with Section 7(b) of the GNU Affero General Public
# License, a covered work must retain the producer line in every PDF that
# is created or manipulated using HexaPDF.
#++

require 'hexapdf/stream'

module HexaPDF
  module Type

    # Represents a form XObject of a PDF document.
    #
    # See: PDF1.7 s8.10
    class Form < Stream

      define_field :Type,          type: Symbol,     default: :XObject
      define_field :Subtype,       type: Symbol,     required: true, default: :Form
      define_field :FormType,      type: Integer,    default: 1
      define_field :BBox,          type: Rectangle,  required: true
      define_field :Matrix,        type: Array
      define_field :Resources,     type: :XXResources, version: '1.2'
      define_field :Group,         type: Dictionary, version: '1.4'
      define_field :Ref,           type: Dictionary, version: '1.4'
      define_field :Metadata,      type: Stream,     version: '1.4'
      define_field :PieceInfo,     type: Dictionary, version: '1.3'
      define_field :LastModified,  type: PDFDate,    version: '1.3'
      define_field :StructParent,  type: Integer,    version: '1.3'
      define_field :StructParents, type: Integer,    version: '1.3'
      define_field :OPI,           type: Dictionary, version: '1.2'
      define_field :OC,            type: Dictionary, version: '1.5'

      # Returns the path to the PDF file that was used when creating the form object.
      #
      # This value is only set when the form object was created by using the image loading
      # facility (i.e. when treating a single page PDF file as image) and not when the form object
      # was created in any other way (i.e. manually created or already part of a loaded PDF file).
      attr_accessor :source_path

      # Returns the rectangle defining the bounding box of the form.
      def box
        self[:BBox]
      end

      # Returns the contents of the form XObject.
      #
      # Note: This is the same as #stream but here for interface compatibility with Page.
      def contents
        stream
      end

      # Replaces the contents of the form XObject with the given string.
      #
      # Note: This is the same as #stream= but here for interface compatibility with Page.
      def contents=(data)
        self.stream = data
      end

      # Returns the resource dictionary which is automatically created if it doesn't exist.
      def resources
        self[:Resources] ||= document.wrap({}, type: :XXResources)
      end

      # Processes the content streams associated with the page with the given processor object.
      #
      # See: HexaPDF::Content::Processor
      def process_contents(processor)
        self[:Resources] = {} if self[:Resources].nil?
        processor.resources = self[:Resources]
        Content::Parser.parse(contents, processor)
      end

    end

  end
end
