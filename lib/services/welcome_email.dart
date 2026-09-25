/// The welcome email new accounts receive — identical to the one the
/// website sends on registration (src/lib/supabase/auth.ts), so a person gets
/// the same message whichever of the two they sign up on.
const String welcomeEmailSubject = 'Welcome to Vasis Studio';

const String welcomeEmailHtml = '''
<div style="font-family: Arial, sans-serif; color: #333; padding: 20px; max-width: 600px; margin: auto;">
  <div style="background: #f3eaff; border: 1px solid #d1b3ff; border-radius: 8px; padding: 14px 18px; margin-bottom: 24px; text-align: center;">
    <h2 style="margin: 0; color: #8637e0; font-size: 22px;">Welcome to Vasis Studio!</h2>
    <p style="margin: 6px 0 0 0; font-size: 15px; color: #555;">We're excited to have you join our community.</p>
  </div>
  <h1 style="text-align: center; color:rgb(134, 55, 224);">Vasis Studio Important Contacts</h1>

  <div style="border: 1px solid #ddd; border-radius: 8px; padding: 16px; margin-bottom: 24px;">
    <h2 style="margin-top: 0; color:rgb(39, 39, 39);">Teacher and Academic Director</h2>
    <p><strong>Giri Govardhan</strong></p>
    <p>
      <a href="https://wa.me/919831724320" style="color: green; text-decoration: none;"> WhatsApp: +91 98317 24320</a><br/>
      <a href="mailto:girigovardana@gmail.com" style="color: #1a73e8; text-decoration: none;">Email: girigovardana@gmail.com</a>
    </p>
    <p style="font-size: 14px; color: #555;">
      Please contact the teacher for all matters related to class attendance, academic progress, and anything concerning your learning experience.
    </p>
  </div>

  <div style="border: 1px solid #ddd; border-radius: 8px; padding: 16px; margin-bottom: 24px;">
    <h2 style="margin-top: 0; color:rgb(39, 39, 39);">Marketing and Sales</h2>
    <p><strong>Nitya K</strong></p>
    <p>
      <a href="https://wa.me/919382008085" style="color: green; text-decoration: none;"> WhatsApp: +91 93820 08085</a><br/>
      <a href="mailto:nityakishora@gmail.com" style="color: #1a73e8; text-decoration: none;">Email: nityakishora@gmail.com</a>
    </p>
    <p style="font-size: 14px; color: #555;">
      Reach out to Nitya for any issues related to payments, deadlines, feedback, partnerships, or if you know anyone interested in joining our courses.
    </p>
  </div>

  <div style="border: 1px solid #ddd; border-radius: 8px; padding: 16px; margin-bottom: 24px;">
    <h2 style="margin-top: 0; color:rgb(39, 39, 39);">Platform Support</h2>
    <p><strong>Keshava Naicker</strong></p>
    <p>
      <a href="https://wa.me/27731108711" style="color: green; text-decoration: none;"> WhatsApp: +27 73 110 8711</a><br/>
      <a href="mailto:mywork.07@outlook.com" style="color: #1a73e8; text-decoration: none;">Email: mywork.07@outlook.com</a>
    </p>
    <p style="font-size: 14px; color: #555;">
      If you are unable to access the platform for any reason, please contact Radha as soon as possible. He's here to resolve any technical issues you might face.
    </p>
  </div>

  <div style="border-left: 4px solid #1a73e8; padding-left: 12px; font-size: 13px; color: #666;">
    <p>
      ⏰ Please keep in mind the time zone difference, as Vasis Studio is based in Mayapur, India. We are here to serve you, so don't hesitate to drop us a message or call whenever needed.
    </p>
  </div>
</div>
''';
